# Tax Analyst Sim

**End-to-end tax operations control and exception-monitoring simulation using PostgreSQL, Python, and Power BI.**

Tax Analyst Sim is a portfolio project designed to simulate the type of data reconciliation, tax reporting, control testing, and process automation performed within a tax operations or tax technology environment.

The project follows tax data from source activity through reporting and exception review:

**Source Data → PostgreSQL → SQL Controls → Python Automation → Power BI Monitoring**

The goal was not simply to identify bad data. It was to build a repeatable control process that:

- validates source data,
- reconciles activity across systems,
- identifies tax-reporting discrepancies,
- distinguishes actionable exceptions from items requiring further review,
- assigns severity and recommended actions, and
- presents results in an operational dashboard.

The simulation focuses on brokerage tax operations including **cost basis, Forms 1099-B and 1042-S, withholding, transaction reporting, and tax-form completeness**. The control-design and automation approach is also transferable to broader corporate tax technology environments where teams reconcile data across systems, automate recurring reviews, and investigate reporting exceptions.

---

## Project Overview

The simulated environment contains five primary datasets:

| Dataset | Records |
|---|---:|
| Accounts | 750 |
| Transactions | 14,298 |
| Cost-basis records | 2,760 |
| Tax forms | 1,198 |
| Withholding records | 904 |

The working dataset intentionally contains corrupted or inconsistent records so that controls can identify and prioritize exceptions.

The project was built in four main stages:

1. **PostgreSQL — Data model and investigation**
2. **SQL — Control design and reconciliation**
3. **Python — Automated exception monitoring**
4. **Power BI — Management reporting and analyst review**

---

## Architecture

```text
Simulated Brokerage Tax Data
            │
            ▼
       PostgreSQL
 accounts | transactions | cost_basis
      tax_forms | withholding
            │
            ▼
      SQL Control Layer
 Data Quality + Reconciliations
            │
            ▼
     Python Automation
 Exception Classification
 Severity + Recommended Action
            │
            ▼
        Power BI
 Control Monitoring Dashboard
 + Exception Review Work Queue
```

---

## 1. PostgreSQL — Building the Tax Operations Environment

The source data was loaded into PostgreSQL as five relational tables:

- `accounts`
- `transactions`
- `cost_basis`
- `tax_forms`
- `withholding`

I used SQL to first understand the data and then progressively build controls around the relationships between operational activity and tax reporting.

A major part of this stage was understanding **data grain** before joining tables.

For example, a single SELL transaction can legitimately have multiple cost-basis records because multiple tax lots may be disposed of in one transaction. What initially appeared to be duplicate transaction IDs in the cost-basis population was therefore a legitimate one-to-many relationship rather than a data-quality failure.

That distinction became important throughout the project: **a control is only useful if the underlying business relationship is understood correctly.**

---

## 2. SQL — Control Design and Reconciliation

After investigating the datasets, I created a reusable SQL control library covering four areas.

### Data Quality Controls

Examples include:

- duplicate primary identifiers,
- missing critical fields,
- orphan transactions,
- negative transaction amounts,
- missing cost basis,
- negative cost basis,
- invalid tax years,
- negative tax-reporting values,
- and missing withholding fields.

### Transaction / Cost-Basis Controls

Examples include:

**SELL proceeds vs. aggregated tax-lot proceeds**

```text
SELL gross amount
        vs.
SUM(cost-basis lot proceeds)
```

**Realized gain/loss**

```text
Realized Gain/Loss
        vs.
Proceeds - Cost Basis
```

**Adjusted gain/loss**

```text
Adjusted Gain/Loss
        vs.
Realized Gain/Loss + Wash Sale Adjustment
```

**Transaction arithmetic**

```text
SELL Gross Amount
        vs.
Quantity × Price
```

### Tax Reporting Controls

The primary reporting reconciliation compares operational activity with Form 1099-B reporting:

```text
SUM(SELL transaction proceeds)
              vs.
1099-B reported proceeds
```

Differences of **$0.01 or less** are treated as rounding rather than substantive exceptions.

Substantive differences are also classified to distinguish recurring exact-dollar adjustment patterns from other reconciliation differences.

### Withholding Controls

Controls include:

- withholding amount vs. gross payment × withholding rate,
- NRA withholding vs. Form 1042-S federal withholding,
- and tax-form completeness reviews associated with backup withholding.

An important design decision was **not** to reconcile all withholding categories against one generic federal-withholding total.

Backup withholding, NRA withholding, and other withholding populations have different reporting destinations. The controls therefore map specific withholding populations to their relevant reporting populations before comparison.

---

## 3. Python — Automated Exception Monitoring

Once the SQL controls were validated, I automated the recurring review process in Python.

The Python script:

1. connects to PostgreSQL,
2. loads the five source tables,
3. executes the control logic,
4. calculates reconciliation differences,
5. classifies exceptions,
6. assigns severity,
7. assigns a recommended action,
8. and produces standardized exception-reporting files.

The process is **read-only**: Python retrieves data from PostgreSQL but does not update the source tables.

### Automated outputs

```text
output/
├── tax_exception_report.csv
└── tax_exception_summary.csv
```

Each exception includes fields such as:

```text
exception_id
control_area
control_name
account_id
transaction_id
exception_type
actual_value
expected_value
difference
severity
recommended_action
classification
account_type
tax_residency
tax_document_type
```

This converts individual control queries into an analyst-ready review population rather than requiring someone to manually inspect the output of each SQL query.

---

## 4. Exception Prioritization

The automated review identified:

| Metric | Result |
|---|---:|
| Actionable exceptions | **69** |
| High severity | **10** |
| Medium severity | **59** |
| Affected accounts | **56** |
| Eligibility review items | **132** |

Severity is based on both the type of control failure and, where appropriate, financial magnitude.

Examples:

**HIGH**
- negative cost basis,
- major reconciliation discrepancies,
- significant tax-reporting exceptions.

**MEDIUM**
- missing cost basis,
- realized or adjusted gain/loss discrepancies,
- withholding calculation discrepancies,
- Form 1099-B proceeds differences.

**REVIEW**
- populations where the available account attributes do not provide enough information to assert that a reporting error occurred.

---

## Control Refinement: Reducing False Positives

One of the most important findings in the project came from the **Form 1099-B completeness control**.

An early version of the control asked:

> Does an account have SELL activity but no Form 1099-B?

Technically, the query worked.

Operationally, it was too broad.

The initial population included many retirement and non-U.S. accounts where the absence of a 1099-B was not enough by itself to conclude that an error had occurred.

I refined the automated control to incorporate:

- `tax_document_type`,
- `account_type`,
- and tax residency context.

Accounts that can reasonably be identified as outside the 1099-B population are excluded, while ambiguous cases are moved to **Eligibility Review** rather than being reported as confirmed HIGH or MEDIUM exceptions.

This reduced false positives and reinforced a central lesson from the project:

> **Control automation requires business judgment in addition to technical accuracy.**

A query can execute perfectly and still produce a poor control if the population or business rules are wrong.

---

## Selected Findings

The automated process reproduced several exception populations identified during the SQL investigation.

### Cost Basis

- **11** missing cost-basis records
- **3** negative cost-basis records
- **14** realized gain/loss calculation discrepancies
- **11** adjusted gain/loss calculation discrepancies

### Form 1099-B Reporting

- **10 substantive proceeds reconciliation exceptions** after removing $0.01 rounding differences
- **8 of the 10** followed exact-dollar adjustment patterns
- two larger reconciliation differences required additional investigation

### Withholding

- **7** withholding calculation exceptions
- **4** NRA withholding vs. Form 1042-S exceptions

Investigation also showed that several downstream reporting differences aligned with upstream calculation exceptions, illustrating how a source-data or calculation issue can propagate through the tax-reporting process.

---

## 5. Power BI — Tax Operations Control Monitoring

The final output is a two-page Power BI report.

### Page 1 — Control Monitoring

The management view summarizes:

- actionable exceptions,
- HIGH and MEDIUM severity populations,
- affected accounts,
- eligibility-review items,
- exceptions by control area,
- exceptions by type,
- and the distribution of severity across controls.

![Tax Operations Control Monitoring](images/dashboard_overview.png)

### Page 2 — Exception Review

The second page functions as an analyst work queue.

Users can filter exceptions by:

- severity,
- control area,
- exception type,
- and account type.

The underlying review table provides the account, transaction, exception, financial difference, classification, and recommended next action.

![Exception Review](images/exception_review.png)

---

## Technology Stack

**PostgreSQL / pgAdmin**
- relational data storage,
- joins and aggregation,
- control testing,
- exception investigation,
- tax-reporting reconciliations.

**SQL**
- data-quality controls,
- transaction-to-tax-lot reconciliation,
- tax-form reconciliation,
- withholding reconciliation,
- exception analysis.

**Python**
- pandas,
- NumPy,
- SQLAlchemy,
- psycopg2,
- PostgreSQL connectivity,
- automated control execution,
- exception classification,
- severity assignment,
- CSV reporting.

**Power BI**
- KPI monitoring,
- control-area analysis,
- exception prioritization,
- analyst filtering and review.

---

## Repository Structure

```text
Tax_Analyst_Sim/
│
├── sql/
│   ├── 01_define_schema.sql
│   ├── 02_data_quality_controls.sql
│   ├── 03_transaction_cost_basis_reconciliation.sql
│   ├── 04_tax_reporting_reconciliation.sql
│   ├── 05_withholding_reconciliation.sql
│   ├── 06_exception_analysis.sql
│   ├── 07_control_library.sql
│   └── 99_investigation_notes.sql
│
├── python/
│   └── run_exception_controls.py
│
├── output/
│   ├── tax_exception_report.csv
│   └── tax_exception_summary.csv
│
├── powerbi/
│   └── Tax_Operations_Control_Monitoring.pbix
│
├── images/
│   ├── dashboard_overview.png
│   └── exception_review.png
│
└── README.md
```

---

## Running the Python Controls

Install dependencies:

```bash
python -m pip install pandas numpy sqlalchemy psycopg2-binary
```

Set the PostgreSQL connection information as environment variables:

```text
DB_NAME
DB_USER
DB_PASSWORD
DB_HOST
DB_PORT
DB_SCHEMA
```

Then run:

```bash
python python/run_exception_controls.py
```

The script generates:

```text
output/tax_exception_report.csv
output/tax_exception_summary.csv
```

Database credentials are intentionally **not hard-coded** into the project.

---

## What I Learned

This project reinforced several principles that apply beyond brokerage tax reporting.

### 1. Understand the business grain before joining data

Multiple rows do not necessarily represent duplicates. The underlying business relationship determines how data should be aggregated and reconciled.

### 2. Reconciliation controls require explicit mappings

It is not enough to compare two totals because they both contain the word "withholding." The underlying populations must represent the same business and reporting activity.

### 3. Materiality matters

A $0.01 rounding difference should not receive the same treatment as a $5,000 reporting discrepancy.

### 4. Automation should reduce noise, not create it

The purpose of a control environment is not to generate the largest possible exception population. It is to identify the population that actually deserves attention.

### 5. Technology supports tax judgment

SQL and Python made the review scalable, but the most important decisions involved understanding what should be compared, determining the correct population, and deciding how an exception should be treated.

---

## Relevance to Tax Operations & Tax Technology

Although the simulation uses brokerage tax data, the underlying workflow is applicable to broader tax functions:

- reconciling source systems to tax-reporting systems,
- automating recurring tax controls,
- validating data before downstream reporting,
- building exception-based review processes,
- documenting control logic,
- prioritizing discrepancies by risk,
- and translating detailed tax data into management reporting.

The project reflects the type of work I am most interested in pursuing: combining **tax knowledge, accounting, data analytics, and automation** to make tax processes more accurate, scalable, and easier to review.

---

## Disclaimer

**Tax Analyst Sim is a simulated educational portfolio project.**

The data is synthetic and does not contain real customer, taxpayer, employer, or client information. The project is intended to demonstrate tax operations, data reconciliation, control design, automation, and analytics skills—not to provide tax advice or represent the systems or processes of any specific company.
