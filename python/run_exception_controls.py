"""
Tax Analyst Sim - Automated Tax Exception Controls
===================================================

Reads five PostgreSQL tables (accounts, transactions, cost_basis, tax_forms,
withholding), runs the control library described in the SQL review, assigns
a severity and a recommended action to every exception, and exports:

    output/tax_exception_report.csv    (one row per exception)
    output/tax_exception_summary.csv   (counts by control and severity)

THIS SCRIPT IS READ-ONLY.
  * It only ever runs SELECT statements.
  * It also asks PostgreSQL to open the session in read-only mode, so even a
    coding mistake could not UPDATE / INSERT / DELETE anything.

Database credentials come from environment variables (see the
"DATABASE CONFIGURATION" section below). Nothing is hard-coded.

Run from a terminal:
    python run_exception_controls.py
"""

import os
import sys
from datetime import date

import numpy as np
import pandas as pd
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import URL


# =============================================================================
# SETTINGS YOU MAY WANT TO REVIEW OR CHANGE
# =============================================================================

# Financial differences of 1 cent or less are treated as normal rounding and
# are NOT reported as exceptions.
TOLERANCE = 0.01

# Reconciliation differences larger than this (in dollars) are HIGH severity
# for the "amount-based" exception types listed further below.
LARGE_DIFFERENCE_THRESHOLD = 1000.00

# 1099-B proceeds differences that are exactly one of these dollar amounts get
# the classification "Exact-dollar adjustment pattern".
EXACT_DOLLAR_ADJUSTMENTS = [50, 250, 500, 1000]

# Tax years earlier than this are treated as impossible (typo / bad load).
# Tax years later than the current calendar year are treated as future dates.
MIN_VALID_TAX_YEAR = 2000

# --- 1099-B ELIGIBILITY SCOPING (used by TR-B and WH-C)  [CHANGED] -----------
# The 1099-B completeness controls should only claim "a 1099-B is missing" for
# accounts that are actually expected to receive one. accounts.tax_document_type
# is used as the account-level designation:
#   * W9           = US person       -> a 1099-B is expected ... EXCEPT that this
#                                       dataset also gives every US IRA a W9, so
#                                       the field alone cannot tell a taxable
#                                       account from an IRA (see below).
#   * W8BEN/W8BENE = non-US person   -> a 1099-B is NOT expected (non-US income
#                                       is reported on a 1042-S), so these
#                                       accounts are out of scope for TR-B/WH-C.
#   * anything else (blank / unrecognized) -> cannot tell -> Eligibility Review.
FORM_1099B_EXPECTED_DOCUMENT_TYPES = ["W9"]
FORM_1099B_NOT_EXPECTED_DOCUMENT_TYPES = ["W8BEN", "W8BENE"]

# Because a W9 does not distinguish retirement accounts, these account types
# are sent to Eligibility Review instead of being reported as a missing 1099-B.
RETIREMENT_ACCOUNT_TYPES = ["TRADITIONAL_IRA", "ROTH_IRA"]

# Severity label for Eligibility Review rows. It is deliberately NOT one of
# HIGH / MEDIUM / LOW, so these rows never count toward those totals.
ELIGIBILITY_REVIEW_SEVERITY = "REVIEW"

# Folder where the two CSV files are written (override with OUTPUT_DIR).
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", "output")


# =============================================================================
# DATABASE CONFIGURATION  (environment variables)
# =============================================================================
# Required:  DB_NAME, DB_USER, DB_PASSWORD
# Optional:  DB_HOST (default localhost), DB_PORT (default 5432),
#            DB_SCHEMA (default: the database's normal search path, "public")

TABLE_NAMES = ["accounts", "transactions", "cost_basis", "tax_forms", "withholding"]

# Columns each table must contain. The script stops with a clear message if any
# are missing, rather than failing halfway through with a confusing error.
REQUIRED_COLUMNS = {
    "accounts": [
        "account_id", "account_type", "tax_residency", "opening_date",
        "tax_document_type",   # [CHANGED] needed for 1099-B eligibility scoping
    ],
    "transactions": [
        "transaction_id", "account_id", "security_symbol", "transaction_type",
        "trade_date", "quantity", "price", "gross_amount",
    ],
    "cost_basis": [
        "basis_record_id", "transaction_id", "account_id", "security_symbol",
        "acquisition_date", "sale_date", "quantity_sold", "cost_basis",
        "proceeds", "realized_gain_loss", "wash_sale_adjustment",
        "adjusted_gain_loss",
    ],
    "tax_forms": [
        "tax_form_id", "account_id", "form_type", "tax_year",
        "reported_proceeds", "reported_cost_basis", "reported_gain_loss",
        "reported_dividends", "reported_interest", "federal_tax_withheld",
    ],
    "withholding": [
        "withholding_id", "account_id", "transaction_id", "withholding_type",
        "income_type", "gross_payment", "withholding_rate",
        "withholding_amount", "withholding_date",
    ],
}

# Columns that must be numbers. PostgreSQL NUMERIC columns can arrive in pandas
# as Decimal objects; converting them to plain numbers makes the math reliable.
NUMERIC_COLUMNS = {
    "transactions": ["quantity", "price", "gross_amount"],
    "cost_basis": [
        "quantity_sold", "cost_basis", "proceeds", "realized_gain_loss",
        "wash_sale_adjustment", "adjusted_gain_loss",
    ],
    "tax_forms": [
        "tax_year", "reported_proceeds", "reported_cost_basis",
        "reported_gain_loss", "reported_dividends", "reported_interest",
        "federal_tax_withheld",
    ],
    "withholding": ["gross_payment", "withholding_rate", "withholding_amount"],
}


# =============================================================================
# SEVERITY AND RECOMMENDED-ACTION RULES
# =============================================================================
# Everything below is a plain dictionary so the rules are easy to read and
# easy to change. Every exception_type produced by a control MUST appear in
# both dictionaries (the script stops with an error if one is missing).

# Base severity for each exception type.
SEVERITY_BY_EXCEPTION_TYPE = {
    # --- HIGH: directly breaks or misstates downstream tax reporting ---
    "Negative Cost Basis": "HIGH",
    "Missing 1099-B With Backup Withholding on Sale Proceeds": "HIGH",
    "Orphan Transaction": "HIGH",

    # --- MEDIUM: affects tax calculations / reporting values ---
    "Missing Cost Basis": "MEDIUM",
    "Missing Cost Basis Field": "MEDIUM",
    "Missing Transaction Field": "MEDIUM",
    "Missing Tax Form Field": "MEDIUM",
    "Missing Withholding Field": "MEDIUM",
    "Invalid Tax Year": "MEDIUM",
    "Negative Tax Reporting Value": "MEDIUM",
    "Negative Transaction Gross Amount": "MEDIUM",
    "Negative Withholding Amount": "MEDIUM",
    "Duplicate Account ID": "MEDIUM",
    "Duplicate Transaction ID": "MEDIUM",
    "Duplicate Basis Record ID": "MEDIUM",
    "Duplicate Tax Form ID": "MEDIUM",
    "Duplicate Withholding ID": "MEDIUM",
    "Withholding Calculation Difference": "MEDIUM",
    "NRA Withholding vs 1042-S Difference": "MEDIUM",
    "Missing 1099-B": "MEDIUM",
    # [CHANGED] Not asserted as an error: 1099-B eligibility could not be
    # confirmed. Excluded from HIGH/MEDIUM/LOW totals via its own label.
    "Eligibility Review": ELIGIBILITY_REVIEW_SEVERITY,
    # Amount-based types: MEDIUM by default, upgraded to HIGH when the
    # difference is larger than LARGE_DIFFERENCE_THRESHOLD (see below).
    "1099-B Proceeds Difference": "MEDIUM",
    "Realized Gain/Loss Mismatch": "MEDIUM",
    "Adjusted Gain/Loss Mismatch": "MEDIUM",
    "SELL Proceeds vs Tax-Lot Proceeds Difference": "MEDIUM",
    "SELL Gross Amount vs Quantity x Price Difference": "MEDIUM",

    # --- LOW: account master-data issues that do not change tax math ---
    "Missing Account Field": "LOW",
    "Future Account Opening Date": "LOW",
}

# Exception types where ABS(difference) > LARGE_DIFFERENCE_THRESHOLD => HIGH.
# The first three come straight from the severity framework. The last two
# (SELL vs tax-lot proceeds, quantity x price) were not named in the framework;
# they follow the same dollar rule - remove them from this set if you disagree.
AMOUNT_BASED_EXCEPTION_TYPES = {
    "1099-B Proceeds Difference",
    "Realized Gain/Loss Mismatch",
    "Adjusted Gain/Loss Mismatch",
    "SELL Proceeds vs Tax-Lot Proceeds Difference",
    "SELL Gross Amount vs Quantity x Price Difference",
}

RECOMMENDED_ACTION_BY_EXCEPTION_TYPE = {
    "Negative Cost Basis":
        "Review acquisition/source basis record and correct invalid basis before downstream tax reporting.",
    "Missing Cost Basis":
        "Research acquisition history and populate missing basis before gain/loss reporting.",
    "Missing Cost Basis Field":
        "Research the source of the missing tax-lot field and populate it before gain/loss and holding-period reporting.",
    "Realized Gain/Loss Mismatch":
        "Recalculate proceeds less cost basis and investigate the source of the reported gain/loss discrepancy.",
    "Adjusted Gain/Loss Mismatch":
        "Recalculate realized gain/loss plus wash sale adjustment and investigate why the stored adjusted amount differs.",
    "SELL Proceeds vs Tax-Lot Proceeds Difference":
        "Compare the SELL transaction to its tax lots and investigate missing, extra, or mis-valued lots.",
    "SELL Gross Amount vs Quantity x Price Difference":
        "Recalculate quantity times price and investigate the source of the booked gross amount.",
    "1099-B Proceeds Difference":
        "Reconcile underlying SELL activity and cost-basis proceeds to tax-form reporting.",
    "Missing 1099-B":
        "Review tax-form generation and reporting eligibility for account with reportable sale activity.",
    "Eligibility Review":   # [CHANGED]
        "Confirm whether this account is eligible for a 1099-B (retirement accounts, for example, are typically reported on other forms). If eligible, investigate form generation; if not, document the exclusion.",
    "Missing 1099-B With Backup Withholding on Sale Proceeds":
        "Escalate: backup withholding was taken on sale proceeds but no 1099-B exists. Confirm the form should have been generated and correct reporting before filing.",
    "Withholding Calculation Difference":
        "Recalculate withholding using gross payment and applicable rate; investigate source calculation.",
    "NRA Withholding vs 1042-S Difference":
        "Trace NRA withholding through 1042-S reporting and investigate the reporting-layer discrepancy.",
    "Orphan Transaction":
        "Locate or restore the missing account record, or correct the transaction's account_id, before reporting.",
    "Missing Account Field":
        "Populate the missing account master-data field from the account-opening records.",
    "Future Account Opening Date":
        "Verify the account opening date against account-opening records and correct the date.",
    "Missing Transaction Field":
        "Research the source trade record and populate the missing transaction field.",
    "Negative Transaction Gross Amount":
        "Review the transaction booking; confirm whether the sign is a data error or a valid reversal.",
    "Missing Tax Form Field":
        "Populate the missing tax-form identifying field before the form is filed.",
    "Invalid Tax Year":
        "Correct the tax year on the form record; confirm the form was generated for the right filing year.",
    "Negative Tax Reporting Value":
        "Review the form value; reported amounts in this field should not be negative.",
    "Missing Withholding Field":
        "Research the source withholding record and populate the missing field.",
    "Negative Withholding Amount":
        "Review the withholding record; confirm whether the negative sign is a data error or a valid reversal.",
    "Duplicate Account ID":
        "Investigate the duplicate account record and merge or remove the extra row in the source system.",
    "Duplicate Transaction ID":
        "Investigate the duplicate transaction identifier in the source system and correct the key.",
    "Duplicate Basis Record ID":
        "Investigate the duplicate cost-basis record identifier and correct the key.",
    "Duplicate Tax Form ID":
        "Investigate the duplicate tax-form identifier and correct the key.",
    "Duplicate Withholding ID":
        "Investigate the duplicate withholding identifier and correct the key.",
}


# =============================================================================
# OUTPUT LAYOUT
# =============================================================================
# Columns every control produces BEFORE severity / action / ID are added.
CONTROL_OUTPUT_COLUMNS = [
    "control_area", "control_name", "account_id", "transaction_id", "record_id",
    "exception_type", "actual_value", "expected_value", "difference",
    "classification", "details",
]

# Final column order in tax_exception_report.csv.
REPORT_COLUMNS = [
    "exception_id", "control_area", "control_name", "account_id",
    "transaction_id", "record_id", "exception_type", "actual_value",
    "expected_value", "difference", "severity", "recommended_action",
    "classification", "details", "account_type", "tax_residency",
    "tax_document_type",   # [CHANGED] added to account context
]

AREA_ORDER = ["Data Quality", "Transaction / Cost Basis", "Tax Reporting", "Withholding"]
SEVERITY_ORDER = ["HIGH", "MEDIUM", "LOW", ELIGIBILITY_REVIEW_SEVERITY]   # [CHANGED] REVIEW sorts last


# =============================================================================
# DATABASE FUNCTIONS
# =============================================================================
def get_database_engine():
    """Build a SQLAlchemy engine from environment variables.

    The session is opened in read-only mode: PostgreSQL itself will refuse
    any write, which guarantees this script cannot change source data.
    """
    database_name = os.environ.get("DB_NAME")
    user = os.environ.get("DB_USER")
    password = os.environ.get("DB_PASSWORD")
    host = os.environ.get("DB_HOST", "localhost")
    port = os.environ.get("DB_PORT", "5432")

    missing = [
        name for name, value in
        [("DB_NAME", database_name), ("DB_USER", user), ("DB_PASSWORD", password)]
        if not value
    ]
    if missing:
        raise EnvironmentError(
            "Missing required environment variable(s): " + ", ".join(missing)
            + ". See the 'DATABASE CONFIGURATION' section of this script."
        )

    # URL.create handles special characters in passwords safely.
    connection_url = URL.create(
        drivername="postgresql+psycopg2",
        username=user,
        password=password,
        host=host,
        port=int(port),
        database=database_name,
    )

    # "default_transaction_read_only=on" makes every session read-only.
    return create_engine(
        connection_url,
        connect_args={"options": "-c default_transaction_read_only=on"},
    )


def load_tables(engine):
    """Read the five source tables into pandas DataFrames (SELECT only).

    Also performs basic safety checks: every table exists, is not empty, and
    has the columns the controls need.
    """
    schema = os.environ.get("DB_SCHEMA") or None

    # Check every required table exists before reading anything.
    inspector = inspect(engine)
    missing_tables = [t for t in TABLE_NAMES if not inspector.has_table(t, schema=schema)]
    if missing_tables:
        raise RuntimeError("Required table(s) not found in database: " + ", ".join(missing_tables))

    tables = {}
    with engine.connect() as connection:
        for table_name in TABLE_NAMES:
            # Table names come from the fixed TABLE_NAMES list above (never
            # from user input), so building the SQL text this way is safe.
            qualified_name = f'"{schema}"."{table_name}"' if schema else f'"{table_name}"'
            tables[table_name] = pd.read_sql_query(
                text(f"SELECT * FROM {qualified_name}"), connection
            )

    return prepare_tables(tables)


def prepare_tables(tables):
    """Validate and tidy the loaded tables (separate from load_tables so the
    checks can be reused/tested without a database connection)."""
    for table_name in TABLE_NAMES:
        if table_name not in tables:
            raise RuntimeError(f"Table '{table_name}' was not loaded.")

        table = tables[table_name]

        # Empty result => almost certainly a connection/schema problem.
        if table.empty:
            raise RuntimeError(f"Table '{table_name}' returned 0 rows. Check the connection and schema.")

        # Use lower-case column names so comparisons are predictable.
        table.columns = [column.lower() for column in table.columns]

        missing_columns = [c for c in REQUIRED_COLUMNS[table_name] if c not in table.columns]
        if missing_columns:
            raise RuntimeError(f"Table '{table_name}' is missing required column(s): {', '.join(missing_columns)}")

        # Convert money/quantity columns to plain numbers (bad text becomes NaN,
        # which the data-quality controls will then report as missing).
        for column in NUMERIC_COLUMNS.get(table_name, []):
            table[column] = pd.to_numeric(table[column], errors="coerce")

        tables[table_name] = table

    return tables


# =============================================================================
# SMALL HELPER FUNCTIONS USED BY MANY CONTROLS
# =============================================================================
def is_missing(series):
    """True where a value is NULL/NaN or only blank spaces."""
    is_null = series.isna()
    is_blank = series.astype(str).str.strip().eq("")
    return is_null | is_blank


def classify_1099b_eligibility(accounts):
    """[NEW] Decide, for each account, whether a 1099-B is expected.

    Returns one row per account_id with:
        eligibility_status : "EXPECTED"     -> in scope; a missing 1099-B is a real exception
                             "NOT_EXPECTED" -> out of scope; no exception and no review item
                             "REVIEW"       -> cannot be confirmed; reported as Eligibility Review
        eligibility_reason : plain-English reason (shown in the report's details column)

    Business purpose: a 1099-B completeness rule should only be applied to
    accounts that are supposed to receive a 1099-B. The rules live in the
    settings at the top of this script so they are easy to review and change.
    """
    document_type = accounts["tax_document_type"].astype(str).str.strip().str.upper()
    account_type = accounts["account_type"].astype(str).str.strip().str.upper()
    document_type_known = accounts["tax_document_type"].notna()
    account_type_known = accounts["account_type"].notna()

    is_expected_document = document_type_known & document_type.isin(FORM_1099B_EXPECTED_DOCUMENT_TYPES)
    is_not_expected_document = document_type_known & document_type.isin(FORM_1099B_NOT_EXPECTED_DOCUMENT_TYPES)
    is_retirement = account_type_known & account_type.isin(RETIREMENT_ACCOUNT_TYPES)

    # Start every account as REVIEW, then overwrite with the clear-cut cases.
    # The order matters: later lines win, so the most specific rules come last.
    status = pd.Series("REVIEW", index=accounts.index)
    reason = pd.Series(
        "tax_document_type is blank or not recognized, so 1099-B eligibility cannot be confirmed",
        index=accounts.index)

    status[is_not_expected_document] = "NOT_EXPECTED"
    reason[is_not_expected_document] = "non-US tax document (W-8): 1099-B not expected"

    status[is_expected_document] = "EXPECTED"
    reason[is_expected_document] = "US tax document (W-9) on a non-retirement account: 1099-B expected"

    # A W-9 is also held by IRAs in this dataset, so it cannot confirm eligibility.
    needs_review = is_expected_document & (is_retirement | ~account_type_known)
    status[needs_review] = "REVIEW"
    reason[needs_review] = (
        "W-9 on a retirement/unknown account type: tax_document_type cannot confirm 1099-B eligibility")

    return pd.DataFrame({
        "account_id": accounts["account_id"],
        "eligibility_status": status,
        "eligibility_reason": reason,
    }).drop_duplicates("account_id")


def exceeds_tolerance(difference):
    """True where the (already rounded) difference is bigger than 1 cent."""
    return difference.abs() > TOLERANCE


def standardize_exceptions(flagged_rows, control_area, control_name, exception_type=None):
    """Put a control's flagged rows into the common exception format.

    Each control builds a small DataFrame with whichever of the columns apply
    (account_id, record_id, actual_value, ...). This function adds the
    constant columns and leaves every column that does not apply BLANK.
    """
    result = flagged_rows.copy()
    result["control_area"] = control_area
    result["control_name"] = control_name
    if exception_type is not None:
        result["exception_type"] = exception_type

    # reindex() creates any missing column (filled with blanks/NaN) and puts
    # the columns in the standard order.
    return result.reindex(columns=CONTROL_OUTPUT_COLUMNS)


def duplicate_id_exceptions(table, id_column, control_name, exception_type, account_column=None):
    """Find IDs that appear more than once and return ONE exception per ID.

    Business purpose: a primary key must be unique; duplicates can cause
    double counting when tables are joined for tax reporting.
    """
    rows_with_id = table[table[id_column].notna()]

    # How many times does each ID appear?
    occurrences = rows_with_id.groupby(id_column).size()
    duplicated_ids = occurrences[occurrences > 1]

    flagged = pd.DataFrame({"record_id": duplicated_ids.index.to_list()})
    flagged["actual_value"] = [f"{count} rows" for count in duplicated_ids.to_list()]
    flagged["expected_value"] = "1 row"
    flagged["details"] = "ID appears more than once in the table"

    # Fill in the account / transaction columns when they are well-defined.
    if id_column == "account_id":
        flagged["account_id"] = flagged["record_id"]
    elif id_column == "transaction_id":
        flagged["transaction_id"] = flagged["record_id"]

    if account_column and id_column != "account_id" and not flagged.empty:
        duplicate_rows = rows_with_id[rows_with_id[id_column].isin(duplicated_ids.index)]
        accounts_by_id = {}
        for duplicate_id, group in duplicate_rows.groupby(id_column):
            distinct_accounts = group[account_column].dropna().unique()
            # Only fill the account when all duplicate rows agree on it.
            accounts_by_id[duplicate_id] = distinct_accounts[0] if len(distinct_accounts) == 1 else None
        flagged["account_id"] = flagged["record_id"].map(accounts_by_id)

    return standardize_exceptions(flagged, "Data Quality", control_name, exception_type)


def missing_field_exceptions(table, fields, record_id_column, control_name, exception_type,
                             account_column="account_id", transaction_column=None):
    """One exception per (record, missing field).

    Business purpose: tax calculations and forms cannot be produced reliably
    when critical identifying fields are NULL or blank.
    """
    pieces = []
    for field in fields:
        rows = table[is_missing(table[field])]
        if rows.empty:
            continue

        has_record_id = ~is_missing(rows[record_id_column])
        details = [
            f"Missing field: {field}" if has_id
            else f"Missing field: {field} (record has no ID; source row index {row_index})"
            for row_index, has_id in zip(rows.index, has_record_id)
        ]

        flagged = pd.DataFrame({"record_id": rows[record_id_column], "details": details})
        if account_column in rows.columns:
            flagged["account_id"] = rows[account_column]
        if transaction_column and transaction_column in rows.columns:
            flagged["transaction_id"] = rows[transaction_column]
        pieces.append(flagged)

    if not pieces:
        return standardize_exceptions(pd.DataFrame(), "Data Quality", control_name, exception_type)

    return standardize_exceptions(pd.concat(pieces), "Data Quality", control_name, exception_type)


def negative_value_exceptions(table, fields, record_id_column, control_name, exception_type,
                              account_column="account_id", transaction_column=None):
    """One exception per (record, negative value) for fields that must be >= 0."""
    pieces = []
    for field in fields:
        rows = table[table[field] < 0]
        if rows.empty:
            continue

        flagged = pd.DataFrame({
            "record_id": rows[record_id_column],
            "actual_value": rows[field],
            "expected_value": ">= 0",
            "details": f"Negative value in field: {field}",
        })
        if account_column in rows.columns:
            flagged["account_id"] = rows[account_column]
        if transaction_column and transaction_column in rows.columns:
            flagged["transaction_id"] = rows[transaction_column]
        pieces.append(flagged)

    if not pieces:
        return standardize_exceptions(pd.DataFrame(), "Data Quality", control_name, exception_type)

    return standardize_exceptions(pd.concat(pieces), "Data Quality", control_name, exception_type)


# =============================================================================
# CONTROL AREA 1 - DATA QUALITY
# =============================================================================
def run_data_quality_controls(tables):
    """Controls DQ-A through DQ-Q. Returns a list of exception DataFrames."""
    accounts = tables["accounts"]
    transactions = tables["transactions"]
    cost_basis = tables["cost_basis"]
    tax_forms = tables["tax_forms"]
    withholding = tables["withholding"]

    results = []

    # ---- ACCOUNTS ----------------------------------------------------------
    # DQ-A: account_id must be unique.
    results.append(duplicate_id_exceptions(
        accounts, "account_id", "DQ-A Duplicate account_id", "Duplicate Account ID"))

    # DQ-B: critical account master-data fields must be populated.
    results.append(missing_field_exceptions(
        accounts, ["account_id", "account_type", "opening_date"], "account_id",
        "DQ-B Missing critical account fields", "Missing Account Field",
        account_column="account_id"))

    # DQ-C: an account cannot be opened in the future.
    opening_dates = pd.to_datetime(accounts["opening_date"], errors="coerce")
    today = pd.Timestamp(date.today())
    future_rows = accounts[opening_dates > today]
    flagged = pd.DataFrame({
        "account_id": future_rows["account_id"],
        "record_id": future_rows["account_id"],
        "actual_value": opening_dates[future_rows.index].dt.strftime("%Y-%m-%d"),
        "expected_value": f"<= {today.strftime('%Y-%m-%d')}",
        "details": "Account opening date is after today's date",
    })
    results.append(standardize_exceptions(
        flagged, "Data Quality", "DQ-C Future account opening dates", "Future Account Opening Date"))

    # ---- TRANSACTIONS ------------------------------------------------------
    # DQ-D: transaction_id must be unique.
    results.append(duplicate_id_exceptions(
        transactions, "transaction_id", "DQ-D Duplicate transaction_id",
        "Duplicate Transaction ID", account_column="account_id"))

    # DQ-E: critical transaction fields must be populated.
    results.append(missing_field_exceptions(
        transactions, ["account_id", "security_symbol", "transaction_type", "trade_date"],
        "transaction_id", "DQ-E Missing critical transaction fields", "Missing Transaction Field",
        account_column="account_id", transaction_column="transaction_id"))

    # DQ-F: every transaction must belong to a known account (referential integrity).
    known_account_ids = set(accounts["account_id"].dropna())
    has_account_id = transactions["account_id"].notna()
    orphan_rows = transactions[has_account_id & ~transactions["account_id"].isin(known_account_ids)]
    flagged = pd.DataFrame({
        "account_id": orphan_rows["account_id"],
        "transaction_id": orphan_rows["transaction_id"],
        "record_id": orphan_rows["transaction_id"],
        "actual_value": orphan_rows["account_id"],
        "expected_value": "account_id exists in accounts",
        "details": "Transaction references an account_id that is not in the accounts table",
    })
    results.append(standardize_exceptions(
        flagged, "Data Quality", "DQ-F Orphan transactions", "Orphan Transaction"))

    # DQ-G: gross_amount should never be negative.
    results.append(negative_value_exceptions(
        transactions, ["gross_amount"], "transaction_id",
        "DQ-G Negative transaction gross_amount", "Negative Transaction Gross Amount",
        account_column="account_id", transaction_column="transaction_id"))

    # ---- COST BASIS --------------------------------------------------------
    # DQ-H: basis_record_id must be unique.
    # NOTE: several rows may legitimately share a transaction_id (one SELL can
    # have many tax lots), so we check basis_record_id only - never transaction_id.
    results.append(duplicate_id_exceptions(
        cost_basis, "basis_record_id", "DQ-H Duplicate basis_record_id",
        "Duplicate Basis Record ID", account_column="account_id"))

    # DQ-I: critical cost-basis fields must be populated (cost_basis itself is
    # reported separately because a missing basis is a meaningful tax exception).
    results.append(missing_field_exceptions(
        cost_basis,
        ["transaction_id", "account_id", "security_symbol", "acquisition_date",
         "sale_date", "quantity_sold", "proceeds", "realized_gain_loss"],
        "basis_record_id", "DQ-I Missing critical cost-basis fields", "Missing Cost Basis Field",
        account_column="account_id", transaction_column="transaction_id"))
    results.append(missing_field_exceptions(
        cost_basis, ["cost_basis"], "basis_record_id",
        "DQ-I Missing critical cost-basis fields", "Missing Cost Basis",
        account_column="account_id", transaction_column="transaction_id"))

    # DQ-J: cost basis cannot be negative.
    results.append(negative_value_exceptions(
        cost_basis, ["cost_basis"], "basis_record_id",
        "DQ-J Negative cost_basis", "Negative Cost Basis",
        account_column="account_id", transaction_column="transaction_id"))

    # ---- TAX FORMS ---------------------------------------------------------
    # DQ-K: tax_form_id must be unique.
    results.append(duplicate_id_exceptions(
        tax_forms, "tax_form_id", "DQ-K Duplicate tax_form_id",
        "Duplicate Tax Form ID", account_column="account_id"))

    # DQ-L: forms need to be identifiable (account, form type, tax year).
    results.append(missing_field_exceptions(
        tax_forms, ["account_id", "form_type", "tax_year"], "tax_form_id",
        "DQ-L Missing tax-form identifying fields", "Missing Tax Form Field",
        account_column="account_id"))

    # DQ-M: tax year must be a plausible, non-future year.
    current_year = date.today().year
    tax_year = tax_forms["tax_year"]
    bad_year_rows = tax_forms[tax_year.notna() & ((tax_year > current_year) | (tax_year < MIN_VALID_TAX_YEAR))]
    flagged = pd.DataFrame({
        "account_id": bad_year_rows["account_id"],
        "record_id": bad_year_rows["tax_form_id"],
        "actual_value": bad_year_rows["tax_year"].astype(int).astype(str),
        "expected_value": f"{MIN_VALID_TAX_YEAR} to {current_year}",
        "details": "Tax year is in the future or impossibly old",
    })
    results.append(standardize_exceptions(
        flagged, "Data Quality", "DQ-M Invalid tax year", "Invalid Tax Year"))

    # DQ-N: these reported amounts can never be negative.
    # (reported_gain_loss is intentionally NOT checked - losses are valid.)
    results.append(negative_value_exceptions(
        tax_forms,
        ["reported_proceeds", "reported_cost_basis", "reported_dividends",
         "reported_interest", "federal_tax_withheld"],
        "tax_form_id", "DQ-N Negative tax-reporting values", "Negative Tax Reporting Value",
        account_column="account_id"))

    # ---- WITHHOLDING -------------------------------------------------------
    # DQ-O: withholding_id must be unique.
    results.append(duplicate_id_exceptions(
        withholding, "withholding_id", "DQ-O Duplicate withholding_id",
        "Duplicate Withholding ID", account_column="account_id"))

    # DQ-P: critical withholding fields must be populated.
    results.append(missing_field_exceptions(
        withholding,
        ["account_id", "transaction_id", "withholding_type", "income_type",
         "gross_payment", "withholding_rate", "withholding_amount", "withholding_date"],
        "withholding_id", "DQ-P Missing critical withholding fields", "Missing Withholding Field",
        account_column="account_id", transaction_column="transaction_id"))

    # DQ-Q: withholding_amount should never be negative.
    results.append(negative_value_exceptions(
        withholding, ["withholding_amount"], "withholding_id",
        "DQ-Q Negative withholding_amount", "Negative Withholding Amount",
        account_column="account_id", transaction_column="transaction_id"))

    return results


# =============================================================================
# CONTROL AREA 2 - TRANSACTION / COST BASIS
# =============================================================================
def run_cost_basis_controls(tables):
    """Controls CB-A through CB-D. Returns a list of exception DataFrames."""
    transactions = tables["transactions"]
    cost_basis = tables["cost_basis"]
    area = "Transaction / Cost Basis"
    results = []

    sell_transactions = transactions[transactions["transaction_type"] == "SELL"]

    # CB-A: SELL gross_amount must equal the SUM of its tax-lot proceeds.
    # One SELL can have several cost_basis rows (tax lots), so we first
    # add the lots up to ONE row per transaction_id, then compare.
    lot_proceeds_by_transaction = (
        cost_basis.groupby("transaction_id", as_index=False)["proceeds"].sum()
        .rename(columns={"proceeds": "lot_proceeds_total"})
    )
    # validate="many_to_one" makes pandas raise an error if the lot totals
    # were NOT unique per transaction (protects against accidental row blow-up).
    sell_vs_lots = sell_transactions.merge(
        lot_proceeds_by_transaction, on="transaction_id", how="left", validate="many_to_one")
    # A SELL with no tax lots at all has lot proceeds of 0.
    sell_vs_lots["lot_proceeds_total"] = sell_vs_lots["lot_proceeds_total"].fillna(0)
    sell_vs_lots = sell_vs_lots[sell_vs_lots["gross_amount"].notna()].copy()
    sell_vs_lots["difference"] = (sell_vs_lots["gross_amount"] - sell_vs_lots["lot_proceeds_total"]).round(2)
    bad_rows = sell_vs_lots[exceeds_tolerance(sell_vs_lots["difference"])]
    flagged = pd.DataFrame({
        "account_id": bad_rows["account_id"],
        "transaction_id": bad_rows["transaction_id"],
        "record_id": bad_rows["transaction_id"],
        "actual_value": bad_rows["gross_amount"],
        "expected_value": bad_rows["lot_proceeds_total"],
        "difference": bad_rows["difference"],
        "details": "actual = SELL gross_amount; expected = SUM of cost_basis proceeds for this transaction",
    })
    results.append(standardize_exceptions(
        flagged, area, "CB-A SELL proceeds vs aggregated tax-lot proceeds",
        "SELL Proceeds vs Tax-Lot Proceeds Difference"))

    # CB-B: realized_gain_loss must equal proceeds - cost_basis.
    # Rows with a NULL input cannot be recalculated; DQ controls report those.
    calculable = cost_basis.dropna(subset=["proceeds", "cost_basis", "realized_gain_loss"]).copy()
    calculable["expected"] = (calculable["proceeds"] - calculable["cost_basis"]).round(2)
    calculable["difference"] = (calculable["realized_gain_loss"] - calculable["expected"]).round(2)
    bad_rows = calculable[exceeds_tolerance(calculable["difference"])]
    flagged = pd.DataFrame({
        "account_id": bad_rows["account_id"],
        "transaction_id": bad_rows["transaction_id"],
        "record_id": bad_rows["basis_record_id"],
        "actual_value": bad_rows["realized_gain_loss"],
        "expected_value": bad_rows["expected"],
        "difference": bad_rows["difference"],
        "details": "expected = proceeds - cost_basis",
    })
    results.append(standardize_exceptions(
        flagged, area, "CB-B Realized gain/loss calculation", "Realized Gain/Loss Mismatch"))

    # CB-C: adjusted_gain_loss must equal realized_gain_loss + wash_sale_adjustment.
    calculable = cost_basis.dropna(
        subset=["realized_gain_loss", "wash_sale_adjustment", "adjusted_gain_loss"]).copy()
    calculable["expected"] = (calculable["realized_gain_loss"] + calculable["wash_sale_adjustment"]).round(2)
    calculable["difference"] = (calculable["adjusted_gain_loss"] - calculable["expected"]).round(2)
    bad_rows = calculable[exceeds_tolerance(calculable["difference"])]
    flagged = pd.DataFrame({
        "account_id": bad_rows["account_id"],
        "transaction_id": bad_rows["transaction_id"],
        "record_id": bad_rows["basis_record_id"],
        "actual_value": bad_rows["adjusted_gain_loss"],
        "expected_value": bad_rows["expected"],
        "difference": bad_rows["difference"],
        "details": "expected = realized_gain_loss + wash_sale_adjustment",
    })
    results.append(standardize_exceptions(
        flagged, area, "CB-C Adjusted gain/loss calculation", "Adjusted Gain/Loss Mismatch"))

    # CB-D: SELL gross_amount must equal quantity x price.
    calculable = sell_transactions.dropna(subset=["quantity", "price", "gross_amount"]).copy()
    calculable["expected"] = (calculable["quantity"] * calculable["price"]).round(2)
    calculable["difference"] = (calculable["gross_amount"] - calculable["expected"]).round(2)
    bad_rows = calculable[exceeds_tolerance(calculable["difference"])]
    flagged = pd.DataFrame({
        "account_id": bad_rows["account_id"],
        "transaction_id": bad_rows["transaction_id"],
        "record_id": bad_rows["transaction_id"],
        "actual_value": bad_rows["gross_amount"],
        "expected_value": bad_rows["expected"],
        "difference": bad_rows["difference"],
        "details": "expected = quantity * price",
    })
    results.append(standardize_exceptions(
        flagged, area, "CB-D SELL gross amount vs quantity x price",
        "SELL Gross Amount vs Quantity x Price Difference"))

    return results


# =============================================================================
# CONTROL AREA 3 - TAX REPORTING
# =============================================================================
def run_tax_reporting_controls(tables):
    """Controls TR-A through TR-C. Returns a list of exception DataFrames."""
    accounts = tables["accounts"]
    transactions = tables["transactions"]
    tax_forms = tables["tax_forms"]
    area = "Tax Reporting"
    results = []

    # Build both populations at the SAME grain (one row per account) before
    # joining them. This avoids many-to-many joins that would double count.
    #
    # "transaction_proceeds" is a CALCULATED value (it is not a database
    # column): the sum of SELL gross_amount for each account.
    sell_transactions = transactions[transactions["transaction_type"] == "SELL"]
    sells_by_account = sell_transactions.groupby("account_id", as_index=False).agg(
        transaction_proceeds=("gross_amount", "sum"),
        sell_count=("transaction_id", "count"),
    )

    forms_1099b = tax_forms[tax_forms["form_type"] == "1099-B"]
    forms_by_account = forms_1099b.groupby("account_id", as_index=False).agg(
        reported_proceeds=("reported_proceeds", "sum"),
        form_count=("tax_form_id", "count"),
        tax_form_ids=("tax_form_id", lambda ids: ", ".join(ids.astype(str))),
    )

    # TR-A / TR-C: compare reported 1099-B proceeds to SELL proceeds, and
    # classify every substantive difference.
    form_vs_sells = forms_by_account.merge(
        sells_by_account, on="account_id", how="left", validate="one_to_one")
    form_vs_sells["transaction_proceeds"] = form_vs_sells["transaction_proceeds"].fillna(0)
    form_vs_sells["difference"] = (
        form_vs_sells["reported_proceeds"] - form_vs_sells["transaction_proceeds"]).round(2)
    bad_rows = form_vs_sells[exceeds_tolerance(form_vs_sells["difference"])].copy()

    # Classification (TR-C): exact dollar amounts such as 50/250/500/1000 look
    # like manual adjustments rather than rounding or data-feed problems.
    is_exact_dollar = bad_rows["difference"].abs().round(2).isin(EXACT_DOLLAR_ADJUSTMENTS)
    classification = np.where(
        is_exact_dollar, "Exact-dollar adjustment pattern", "Other proceeds reconciliation difference")

    flagged = pd.DataFrame({
        "account_id": bad_rows["account_id"],
        "record_id": bad_rows["tax_form_ids"],
        "actual_value": bad_rows["reported_proceeds"],
        "expected_value": bad_rows["transaction_proceeds"],
        "difference": bad_rows["difference"],
        "classification": classification,
        "details": "actual = 1099-B reported_proceeds; expected = SUM of SELL gross_amount for the account",
    })
    results.append(standardize_exceptions(
        flagged, area, "TR-A/TR-C 1099-B proceeds reconciliation and classification",
        "1099-B Proceeds Difference"))

    # TR-B: accounts that SOLD securities but have no 1099-B at all.
    # This is a completeness / reporting-lineage question, NOT a confirmed tax
    # error: some accounts (for example retirement or non-US accounts) may not
    # be eligible for a 1099-B. Account type/residency are shown for triage.
    #
    # [CHANGED] The rule is now scoped by 1099-B eligibility (see
    # classify_1099b_eligibility):
    #   EXPECTED     -> reported below as "Missing 1099-B" (MEDIUM)
    #   REVIEW       -> reported as "Eligibility Review" (not HIGH/MEDIUM)
    #   NOT_EXPECTED -> out of scope, not reported at all
    account_context = accounts.drop_duplicates("account_id")[
        ["account_id", "account_type", "tax_residency", "tax_document_type"]]   # [CHANGED] + tax_document_type
    eligibility = classify_1099b_eligibility(accounts)

    sells_without_form = sells_by_account.merge(
        forms_by_account[["account_id", "form_count"]], on="account_id", how="left", validate="one_to_one")
    sells_without_form = sells_without_form[sells_without_form["form_count"].isna()]
    sells_without_form = sells_without_form.merge(
        account_context, on="account_id", how="left", validate="many_to_one")
    sells_without_form = sells_without_form.merge(
        eligibility, on="account_id", how="left", validate="many_to_one")
    # An account that is not in the accounts table at all cannot be scoped.
    sells_without_form["eligibility_status"] = sells_without_form["eligibility_status"].fillna("REVIEW")
    sells_without_form["eligibility_reason"] = sells_without_form["eligibility_reason"].fillna(
        "account not found in accounts table, so 1099-B eligibility cannot be confirmed")

    # Accounts a 1099-B is NOT expected for are dropped from this control.
    sells_without_form = sells_without_form[sells_without_form["eligibility_status"] != "NOT_EXPECTED"]
    expected_rows = sells_without_form[sells_without_form["eligibility_status"] == "EXPECTED"]
    review_rows = sells_without_form[sells_without_form["eligibility_status"] == "REVIEW"]

    # --- confirmed in-scope accounts: a real completeness exception ---
    details = [
        f"{int(count)} SELL transaction(s); account_type={account_type}; tax_residency={residency}; "
        f"tax_document_type={document_type}; "
        "no 1099-B record found - investigate reporting eligibility/form generation"
        for count, account_type, residency, document_type in zip(
            expected_rows["sell_count"],
            expected_rows["account_type"].fillna("unknown"),
            expected_rows["tax_residency"].fillna("unknown"),
            expected_rows["tax_document_type"].fillna("unknown"))
    ]
    flagged = pd.DataFrame({
        "account_id": expected_rows["account_id"],
        "actual_value": 0.0,       # no 1099-B proceeds are reported
        "expected_value": expected_rows["transaction_proceeds"],
        "difference": (0.0 - expected_rows["transaction_proceeds"]).round(2),
        "classification": "Tax-form completeness / reporting-lineage exception",
        "details": details,
    })
    results.append(standardize_exceptions(
        flagged, area, "TR-B 1099-B completeness", "Missing 1099-B"))

    # --- eligibility could not be confirmed: review item, NOT an asserted error ---
    details = [
        f"{int(count)} SELL transaction(s); account_type={account_type}; tax_residency={residency}; "
        f"tax_document_type={document_type}; no 1099-B record found; {reason}"
        for count, account_type, residency, document_type, reason in zip(
            review_rows["sell_count"],
            review_rows["account_type"].fillna("unknown"),
            review_rows["tax_residency"].fillna("unknown"),
            review_rows["tax_document_type"].fillna("unknown"),
            review_rows["eligibility_reason"])
    ]
    flagged = pd.DataFrame({
        "account_id": review_rows["account_id"],
        "actual_value": 0.0,
        "expected_value": review_rows["transaction_proceeds"],
        "difference": (0.0 - review_rows["transaction_proceeds"]).round(2),
        "classification": "Eligibility Review",
        "details": details,
    })
    results.append(standardize_exceptions(
        flagged, area, "TR-B 1099-B completeness", "Eligibility Review"))

    return results


# =============================================================================
# CONTROL AREA 4 - WITHHOLDING
# =============================================================================
def run_withholding_controls(tables):
    """Controls WH-A through WH-C. Returns a list of exception DataFrames."""
    accounts = tables["accounts"]   # [CHANGED] needed for 1099-B eligibility scoping in WH-C
    tax_forms = tables["tax_forms"]
    withholding = tables["withholding"]
    area = "Withholding"
    results = []

    # WH-A: withholding_amount must equal gross_payment x withholding_rate.
    calculable = withholding.dropna(subset=["gross_payment", "withholding_rate", "withholding_amount"]).copy()
    calculable["expected"] = (calculable["gross_payment"] * calculable["withholding_rate"]).round(2)
    calculable["difference"] = (calculable["withholding_amount"] - calculable["expected"]).round(2)
    bad_rows = calculable[exceeds_tolerance(calculable["difference"])]
    flagged = pd.DataFrame({
        "account_id": bad_rows["account_id"],
        "transaction_id": bad_rows["transaction_id"],
        "record_id": bad_rows["withholding_id"],
        "actual_value": bad_rows["withholding_amount"],
        "expected_value": bad_rows["expected"],
        "difference": bad_rows["difference"],
        "details": "expected = gross_payment * withholding_rate",
    })
    results.append(standardize_exceptions(
        flagged, area, "WH-A Withholding calculation", "Withholding Calculation Difference"))

    # WH-B: NRA withholding must flow to the 1042-S.
    # Only NRA_WITHHOLDING is compared (backup/state withholding feed other
    # forms). Each side is added up to ONE row per account BEFORE joining.
    nra_by_account = (
        withholding[withholding["withholding_type"] == "NRA_WITHHOLDING"]
        .groupby("account_id", as_index=False)
        .agg(nra_withholding=("withholding_amount", "sum"), nra_records=("withholding_id", "count"))
    )
    forms_1042s_by_account = (
        tax_forms[tax_forms["form_type"] == "1042-S"]
        .groupby("account_id", as_index=False)
        .agg(
            reported_withheld=("federal_tax_withheld", "sum"),
            tax_form_ids=("tax_form_id", lambda ids: ", ".join(ids.astype(str))),
        )
    )
    # "outer" keeps accounts that appear on only one side (for example NRA
    # withholding with no 1042-S, or a 1042-S with no NRA withholding).
    nra_vs_form = nra_by_account.merge(
        forms_1042s_by_account, on="account_id", how="outer", validate="one_to_one")
    has_form = nra_vs_form["tax_form_ids"].notna()
    has_nra = nra_vs_form["nra_records"].notna()
    nra_vs_form["nra_withholding"] = nra_vs_form["nra_withholding"].fillna(0)
    nra_vs_form["reported_withheld"] = nra_vs_form["reported_withheld"].fillna(0)
    nra_vs_form["difference"] = (nra_vs_form["reported_withheld"] - nra_vs_form["nra_withholding"]).round(2)

    bad_rows = nra_vs_form[exceeds_tolerance(nra_vs_form["difference"])]
    details = []
    for row_index in bad_rows.index:
        if not has_form[row_index]:
            details.append("NRA withholding exists but no 1042-S record was found")
        elif not has_nra[row_index]:
            details.append("1042-S reports federal tax withheld but no NRA withholding records exist")
        else:
            details.append("actual = 1042-S federal_tax_withheld; expected = SUM of NRA_WITHHOLDING")
    flagged = pd.DataFrame({
        "account_id": bad_rows["account_id"],
        "record_id": bad_rows["tax_form_ids"],       # blank when there is no 1042-S
        "actual_value": bad_rows["reported_withheld"],
        "expected_value": bad_rows["nra_withholding"],
        "difference": bad_rows["difference"],
        "details": details,
    })
    results.append(standardize_exceptions(
        flagged, area, "WH-B NRA withholding vs 1042-S", "NRA Withholding vs 1042-S Difference"))

    # WH-C: backup withholding taken on SALE PROCEEDS requires a 1099-B.
    backup_on_sales = withholding[
        (withholding["withholding_type"] == "BACKUP_WITHHOLDING")
        & (withholding["income_type"] == "SALE_PROCEEDS")
    ]
    backup_by_account = backup_on_sales.groupby("account_id", as_index=False).agg(
        backup_withholding=("withholding_amount", "sum"),
        backup_records=("withholding_id", "count"),
    )
    accounts_with_1099b = set(tax_forms.loc[tax_forms["form_type"] == "1099-B", "account_id"].dropna())
    missing_form = backup_by_account[~backup_by_account["account_id"].isin(accounts_with_1099b)]

    # [CHANGED] Scope by 1099-B eligibility, exactly as TR-B does:
    #   EXPECTED     -> "Missing 1099-B With Backup Withholding..." (HIGH)
    #   REVIEW       -> "Eligibility Review" (not HIGH/MEDIUM)
    #   NOT_EXPECTED -> out of scope, not reported at all
    eligibility = classify_1099b_eligibility(accounts)
    missing_form = missing_form.merge(
        eligibility, on="account_id", how="left", validate="many_to_one")
    missing_form["eligibility_status"] = missing_form["eligibility_status"].fillna("REVIEW")
    missing_form["eligibility_reason"] = missing_form["eligibility_reason"].fillna(
        "account not found in accounts table, so 1099-B eligibility cannot be confirmed")

    missing_form = missing_form[missing_form["eligibility_status"] != "NOT_EXPECTED"]
    expected_rows = missing_form[missing_form["eligibility_status"] == "EXPECTED"]
    review_rows = missing_form[missing_form["eligibility_status"] == "REVIEW"]

    # --- confirmed in-scope accounts: backup withholding with no 1099-B ---
    details = [
        f"{int(count)} backup-withholding record(s) on SALE_PROCEEDS; no 1099-B exists for this account"
        for count in expected_rows["backup_records"]
    ]
    flagged = pd.DataFrame({
        "account_id": expected_rows["account_id"],
        "actual_value": 0.0,    # nothing is reported on a 1099-B (no form exists)
        "expected_value": expected_rows["backup_withholding"],
        "difference": (0.0 - expected_rows["backup_withholding"]).round(2),
        "details": details,
    })
    results.append(standardize_exceptions(
        flagged, area, "WH-C Backup withholding on sale proceeds vs 1099-B completeness",
        "Missing 1099-B With Backup Withholding on Sale Proceeds"))

    # --- eligibility could not be confirmed: review item, NOT an asserted error ---
    details = [
        f"{int(count)} backup-withholding record(s) on SALE_PROCEEDS; no 1099-B exists; {reason}"
        for count, reason in zip(review_rows["backup_records"], review_rows["eligibility_reason"])
    ]
    flagged = pd.DataFrame({
        "account_id": review_rows["account_id"],
        "actual_value": 0.0,
        "expected_value": review_rows["backup_withholding"],
        "difference": (0.0 - review_rows["backup_withholding"]).round(2),
        "classification": "Eligibility Review",
        "details": details,
    })
    results.append(standardize_exceptions(
        flagged, area, "WH-C Backup withholding on sale proceeds vs 1099-B completeness",
        "Eligibility Review"))

    return results


# =============================================================================
# SEVERITY AND RECOMMENDED ACTION
# =============================================================================
def assign_severity(exceptions):
    """Add a 'severity' column using SEVERITY_BY_EXCEPTION_TYPE plus the
    dollar-threshold rule for amount-based exception types."""
    unknown_types = set(exceptions["exception_type"]) - set(SEVERITY_BY_EXCEPTION_TYPE)
    if unknown_types:
        raise ValueError(f"No severity rule defined for exception type(s): {sorted(unknown_types)}")

    result = exceptions.copy()
    result["severity"] = result["exception_type"].map(SEVERITY_BY_EXCEPTION_TYPE)

    # Upgrade amount-based exceptions to HIGH when the difference is large.
    is_amount_based = result["exception_type"].isin(AMOUNT_BASED_EXCEPTION_TYPES)
    is_large = result["difference"].abs() > LARGE_DIFFERENCE_THRESHOLD
    result.loc[is_amount_based & is_large, "severity"] = "HIGH"
    return result


def assign_recommended_action(exceptions):
    """Add a 'recommended_action' column based on the exception type."""
    unknown_types = set(exceptions["exception_type"]) - set(RECOMMENDED_ACTION_BY_EXCEPTION_TYPE)
    if unknown_types:
        raise ValueError(f"No recommended action defined for exception type(s): {sorted(unknown_types)}")

    result = exceptions.copy()
    result["recommended_action"] = result["exception_type"].map(RECOMMENDED_ACTION_BY_EXCEPTION_TYPE)
    return result


# =============================================================================
# BUILD THE REPORT AND SUMMARY
# =============================================================================
def format_value(value):
    """Make actual/expected values tidy text: money with 2 decimals, blanks as empty."""
    if pd.isna(value):
        return ""
    if isinstance(value, (int, np.integer)):
        return str(int(value))
    if isinstance(value, (float, np.floating)):
        return f"{value:.2f}"
    return str(value)


def build_exception_report(exception_frames, accounts):
    """Combine all control outputs into the final exception report.

    `accounts` is only used to add two context columns (account_type and
    tax_residency) so exceptions can be filtered, for example to separate
    retirement or non-US accounts from US taxable accounts.
    """
    # Drop empty frames so pandas does not warn when concatenating them.
    non_empty_frames = [frame for frame in exception_frames if not frame.empty]
    if non_empty_frames:
        report = pd.concat(non_empty_frames, ignore_index=True)
    else:
        report = pd.DataFrame(columns=CONTROL_OUTPUT_COLUMNS)

    report["difference"] = pd.to_numeric(report["difference"], errors="coerce").round(2)

    report = assign_severity(report)
    report = assign_recommended_action(report)

    # Context columns: look each account up by account_id. Using map() (a
    # lookup) instead of merge() guarantees no rows can be duplicated.
    account_lookup = accounts.drop_duplicates("account_id").set_index("account_id")
    report["account_type"] = report["account_id"].map(account_lookup["account_type"])
    report["tax_residency"] = report["account_id"].map(account_lookup["tax_residency"])
    report["tax_document_type"] = report["account_id"].map(account_lookup["tax_document_type"])   # [CHANGED]

    # Tidy text for the mixed-type value columns (blank stays blank).
    report["actual_value"] = report["actual_value"].map(format_value)
    report["expected_value"] = report["expected_value"].map(format_value)

    # Sequential IDs: EXC000001, EXC000002, ...
    report.insert(0, "exception_id", [f"EXC{number:06d}" for number in range(1, len(report) + 1)])
    report = report.reindex(columns=REPORT_COLUMNS)

    # Safety checks on our own output.
    columns_without_id = [c for c in REPORT_COLUMNS if c != "exception_id"]
    duplicate_count = int(report.duplicated(subset=columns_without_id).sum())
    if duplicate_count > 0:
        raise AssertionError(f"{duplicate_count} accidental duplicate exception row(s) were generated.")
    if not report["exception_id"].is_unique:
        raise AssertionError("exception_id values are not unique.")
    if report["severity"].isna().any():
        raise AssertionError("Some exceptions have no severity.")

    return report


def build_exception_summary(report):
    """Summarize exceptions by control_area, control_name and severity."""
    working = report.copy()
    working["absolute_difference"] = working["difference"].abs()

    summary = working.groupby(["control_area", "control_name", "severity"], as_index=False).agg(
        exception_count=("exception_id", "count"),
        # min_count=1 => stays blank (NaN) when no row has a dollar difference
        total_absolute_difference=("absolute_difference", lambda values: values.sum(min_count=1)),
    )
    summary["total_absolute_difference"] = summary["total_absolute_difference"].round(2)

    # Sort in a meaningful order rather than alphabetically.
    summary["area_rank"] = summary["control_area"].map({a: i for i, a in enumerate(AREA_ORDER)})
    summary["severity_rank"] = summary["severity"].map({s: i for i, s in enumerate(SEVERITY_ORDER)})
    summary = summary.sort_values(["area_rank", "control_name", "severity_rank"])
    return summary.drop(columns=["area_rank", "severity_rank"]).reset_index(drop=True)


# =============================================================================
# MAIN
# =============================================================================
def main():
    engine = get_database_engine()
    tables = load_tables(engine)

    # Run every control area; each returns a list of DataFrames.
    exception_frames = []
    exception_frames += run_data_quality_controls(tables)
    exception_frames += run_cost_basis_controls(tables)
    exception_frames += run_tax_reporting_controls(tables)
    exception_frames += run_withholding_controls(tables)

    report = build_exception_report(exception_frames, tables["accounts"])
    summary = build_exception_summary(report)

    # Write the two CSV files (blank cells are written as empty strings).
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    report_path = os.path.join(OUTPUT_DIR, "tax_exception_report.csv")
    summary_path = os.path.join(OUTPUT_DIR, "tax_exception_summary.csv")
    report.to_csv(report_path, index=False)
    summary.to_csv(summary_path, index=False)

    # Reasonableness figure for the SQL-review finding (computed, not hard-coded).
    backup_missing_1099b = report[
        report["exception_type"] == "Missing 1099-B With Backup Withholding on Sale Proceeds"]
    backup_amount = backup_missing_1099b["expected_value"].astype(float).sum()

    # [CHANGED] Same backup-withholding finding, but for accounts whose 1099-B
    # eligibility could not be confirmed (shown separately, never as HIGH).
    backup_review = report[
        (report["exception_type"] == "Eligibility Review")
        & report["control_name"].str.startswith("WH-C")]
    backup_review_amount = backup_review["expected_value"].astype(float).sum()

    # [CHANGED] Eligibility Review rows are counted separately and are NOT part
    # of "Exceptions identified" or the High/Medium/Low totals.
    severity_counts = report["severity"].value_counts()
    review_count = int(severity_counts.get(ELIGIBILITY_REVIEW_SEVERITY, 0))
    exception_count = len(report) - review_count

    # [CHANGED] How many accounts fall in each 1099-B eligibility bucket.
    eligibility_counts = classify_1099b_eligibility(tables["accounts"])["eligibility_status"].value_counts()
    print()
    print("Tax Analyst Sim - Automated Review Complete")
    print()
    print(f"Accounts reviewed: {len(tables['accounts']):,}")
    print(f"Transactions reviewed: {len(tables['transactions']):,}")
    print(f"Cost-basis records reviewed: {len(tables['cost_basis']):,}")
    print(f"Tax forms reviewed: {len(tables['tax_forms']):,}")
    print(f"Withholding records reviewed: {len(tables['withholding']):,}")
    print()
    print(f"Exceptions identified: {exception_count:,}")
    print(f"High severity: {int(severity_counts.get('HIGH', 0)):,}")
    print(f"Medium severity: {int(severity_counts.get('MEDIUM', 0)):,}")
    print(f"Low severity: {int(severity_counts.get('LOW', 0)):,}")
    print(f"Eligibility Review items (not counted above): {review_count:,}")
    print()
    print("1099-B eligibility scoping (accounts by tax_document_type / account type):")
    print(f"  Expected to receive a 1099-B:       {int(eligibility_counts.get('EXPECTED', 0)):,}")
    print(f"  Not expected (non-US, out of scope): {int(eligibility_counts.get('NOT_EXPECTED', 0)):,}")
    print(f"  Cannot be confirmed (review):        {int(eligibility_counts.get('REVIEW', 0)):,}")
    print()
    print("Reasonableness check - backup withholding on sale proceeds with no 1099-B:")
    print(f"  In-scope accounts (HIGH):          {len(backup_missing_1099b):,}   Backup withholding: ${backup_amount:,.2f}")
    print(f"  Eligibility Review (not HIGH):     {len(backup_review):,}   Backup withholding: ${backup_review_amount:,.2f}")
    print("  (Compare the combined figure with your SQL investigation result.)")
    print()
    print("Output:")
    print(f"  {report_path}")
    print(f"  {summary_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Print a short, readable message instead of a long traceback, and
        # exit with a non-zero code so schedulers can detect the failure.
        print(f"\nERROR: {error}", file=sys.stderr)
        sys.exit(1)
