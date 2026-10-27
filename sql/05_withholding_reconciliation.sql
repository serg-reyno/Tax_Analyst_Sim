-- Tax Analyst Sim | 05_withholding_reconciliation
-- Purpose: Validate withholding calculations and trace amounts into reporting.
-- Files 02-06 are SELECT-only and use the existing imported tables.
-- Expected results describe a clean baseline; corrupted data can return exceptions.
-- Scope: Original reporting comparisons assume one reporting year and one applicable form
-- per account/form type. Resolve duplicate forms and statuses before relying on totals.
-- Federal reporting comparisons require category mapping; do not treat all withholding as federal.

-- ======================================================================================================
-- WITHHOLDING RECONCILIATION
-- ======================================================================================================

-- Control 1: Review withholding activity
-- Expected result: Identify the types of withholding activity present
-- before performing the account-level reconciliation.

SELECT
    withholding_type,
    income_type,
    documentation_status,
    COUNT(*) AS withholding_count,
    SUM(gross_payment) AS total_gross_payment,
    SUM(withholding_amount) AS total_withholding
FROM withholding
GROUP BY
    withholding_type,
    income_type,
    documentation_status
ORDER BY withholding_count DESC;

-- ======================================================================================================
-- WITHHOLDING RECONCILIATION
-- ======================================================================================================

-- Control 2: Validate withholding calculation
-- Expected result: Withholding amount should equal gross payment multiplied
-- by withholding rate, allowing for $0.01 rounding.

SELECT
    withholding_id,
    account_id,
    transaction_id,
    withholding_type,
    income_type,
    gross_payment,
    withholding_rate,
    withholding_amount,
    gross_payment * withholding_rate AS calculated_withholding,
    withholding_amount - (gross_payment * withholding_rate) AS difference
FROM withholding
WHERE ABS(
    withholding_amount - (gross_payment * withholding_rate)
) > 0.01;

-- ======================================================================================================
-- WITHHOLDING TO TAX FORM RECONCILIATION
-- ======================================================================================================
-- Control: Reconcile total withholding activity to federal tax withheld
-- reported on tax forms by account and tax year.
--
-- Expected result: Withholding totals should reconcile to tax-form
-- federal withholding within $0.01.

WITH withholding_summary AS (
    SELECT
        account_id,
        EXTRACT(YEAR FROM withholding_date)::INTEGER AS tax_year,
        SUM(withholding_amount) AS total_withholding
    FROM withholding
    GROUP BY
        account_id,
        EXTRACT(YEAR FROM withholding_date)
),

tax_form_summary AS (
    SELECT
        account_id,
        tax_year,
        SUM(federal_tax_withheld) AS reported_federal_withholding
    FROM tax_forms
    GROUP BY
        account_id,
        tax_year
)

SELECT
    w.account_id,
    w.tax_year,
    w.total_withholding,
    COALESCE(t.reported_federal_withholding, 0) AS reported_federal_withholding,
    w.total_withholding
        - COALESCE(t.reported_federal_withholding, 0) AS difference
FROM withholding_summary w
LEFT JOIN tax_form_summary t
    ON w.account_id = t.account_id
   AND w.tax_year = t.tax_year
WHERE ABS(
    w.total_withholding
        - COALESCE(t.reported_federal_withholding, 0)
) > 0.01
ORDER BY ABS(
    w.total_withholding
        - COALESCE(t.reported_federal_withholding, 0)
) DESC;

-- Investigation: Review tax form types
-- Expected result: Identify which tax forms exist in the dataset
-- and determine which forms may contain federal withholding.

SELECT
    form_type,
    COUNT(*) AS form_count,
    SUM(federal_tax_withheld) AS total_federal_withholding
FROM tax_forms
GROUP BY form_type
ORDER BY form_count DESC;

-- Investigation: Review withholding by withholding type
-- Expected result: Understand which withholding categories exist
-- before determining which categories should reconcile to federal tax reporting.

SELECT
    withholding_type,
    COUNT(*) AS record_count,
    SUM(gross_payment) AS total_gross_payment,
    SUM(withholding_amount) AS total_withholding
FROM withholding
GROUP BY withholding_type
ORDER BY total_withholding DESC;

-- Investigation: Review withholding type and income type combinations
-- Expected result: Identify the business relationships between
-- withholding categories and underlying income types.

SELECT
    withholding_type,
    income_type,
    COUNT(*) AS record_count,
    SUM(withholding_amount) AS total_withholding
FROM withholding
GROUP BY
    withholding_type,
    income_type
ORDER BY
    withholding_type,
    total_withholding DESC;

-- ======================================================================================================
-- NRA WITHHOLDING TO 1042-S RECONCILIATION
-- ======================================================================================================
-- Control: Compare NRA withholding to 1042-S federal withholding
-- by account.
--
-- Expected result: Differences greater than $0.01 should be investigated.

WITH nra_summary AS (
    SELECT
        account_id,
        SUM(withholding_amount) AS nra_withholding
    FROM withholding
    WHERE withholding_type = 'NRA_WITHHOLDING'
    GROUP BY account_id
),

form_summary AS (
    SELECT
        account_id,
        SUM(federal_tax_withheld) AS reported_1042s_withholding
    FROM tax_forms
    WHERE form_type = '1042-S'
    GROUP BY account_id
)

SELECT
    n.account_id,
    n.nra_withholding,
    COALESCE(f.reported_1042s_withholding, 0) AS reported_1042s_withholding,
    n.nra_withholding
        - COALESCE(f.reported_1042s_withholding, 0) AS difference
FROM nra_summary n
LEFT JOIN form_summary f
    ON n.account_id = f.account_id
WHERE ABS(
    n.nra_withholding
        - COALESCE(f.reported_1042s_withholding, 0)
) > 0.01
ORDER BY ABS(
    n.nra_withholding
        - COALESCE(f.reported_1042s_withholding, 0)
) DESC;

-- Investigation: Review backup withholding by income type
-- Expected result: Identify the backup-withholding populations that
-- may correspond to specific 1099 reporting forms.

SELECT
    income_type,
    COUNT(*) AS record_count,
    SUM(withholding_amount) AS total_withholding
FROM withholding
WHERE withholding_type = 'BACKUP_WITHHOLDING'
GROUP BY income_type
ORDER BY total_withholding DESC;

-- ======================================================================================================
-- BACKUP WITHHOLDING: SALE PROCEEDS TO 1099-B RECONCILIATION
-- ======================================================================================================
-- Control: Compare backup withholding associated with sale proceeds
-- to federal tax withholding reported on 1099-B forms by account.
--
-- Expected result: Differences greater than $0.01 should be investigated.

WITH backup_sale_summary AS (
    SELECT
        account_id,
        SUM(withholding_amount) AS backup_sale_withholding
    FROM withholding
    WHERE withholding_type = 'BACKUP_WITHHOLDING'
      AND income_type = 'SALE_PROCEEDS'
    GROUP BY account_id
),



form_summary AS (
    SELECT
        account_id,
        SUM(federal_tax_withheld) AS reported_1099b_withholding
    FROM tax_forms
    WHERE form_type = '1099-B'
    GROUP BY account_id
)

SELECT
    b.account_id,
    b.backup_sale_withholding,
    COALESCE(f.reported_1099b_withholding, 0) AS reported_1099b_withholding,
    b.backup_sale_withholding
        - COALESCE(f.reported_1099b_withholding, 0) AS difference
FROM backup_sale_summary b
LEFT JOIN form_summary f
    ON b.account_id = f.account_id
WHERE ABS(
    b.backup_sale_withholding
        - COALESCE(f.reported_1099b_withholding, 0)
) > 0.01
ORDER BY ABS(
    b.backup_sale_withholding
        - COALESCE(f.reported_1099b_withholding, 0)
) DESC;

-- ======================================================================================================
-- MISSING 1099-B CHECK FOR BACKUP-WITHHELD SALE PROCEEDS
-- ======================================================================================================
-- Control: Identify accounts with backup withholding on sale proceeds
-- that do not have a corresponding 1099-B tax form.
--
-- Expected result: Every account with reportable sale activity should have
-- an appropriate 1099-B record. Exceptions should be investigated.

SELECT
    b.account_id,
    COUNT(*) AS withholding_records,
    SUM(b.withholding_amount) AS total_backup_withholding
FROM withholding b
LEFT JOIN tax_forms f
    ON b.account_id = f.account_id
   AND f.form_type = '1099-B'
WHERE b.withholding_type = 'BACKUP_WITHHOLDING'
  AND b.income_type = 'SALE_PROCEEDS'
  AND f.tax_form_id IS NULL
GROUP BY b.account_id
ORDER BY total_backup_withholding DESC;
