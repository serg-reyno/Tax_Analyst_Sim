-- ======================================================================================================
-- Tax Analyst Sim | 07_control_library.sql
-- Purpose: Final reusable SQL control library selected from the Phase 3 investigation.
-- ======================================================================================================

-- ======================================================================================================
-- 1. DATA-QUALITY CONTROLS
-- ======================================================================================================

-- 1.1 ACCOUNTS: Duplicate account IDs
-- Expected result: 0 duplicate account IDs.
SELECT account_id, COUNT(*) AS duplicate_count
FROM accounts
GROUP BY account_id
HAVING COUNT(*) > 1;

-- 1.2 ACCOUNTS: Missing critical fields
-- Expected result: 0 accounts with missing critical fields.
SELECT account_id
FROM accounts
WHERE account_id IS NULL
   OR account_type IS NULL
   OR opening_date IS NULL;

-- 1.3 ACCOUNTS: Future opening dates
-- Expected result: 0 accounts with an opening date after the current date.
SELECT account_id, opening_date
FROM accounts
WHERE opening_date > CURRENT_DATE;

-- 1.4 TRANSACTIONS: Duplicate transaction IDs
-- Expected result: 0 duplicate transaction IDs.
SELECT transaction_id, COUNT(*) AS duplicate_count
FROM transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1;

-- 1.5 TRANSACTIONS: Missing critical fields
-- Expected result: 0 transactions with missing critical fields.
SELECT transaction_id
FROM transactions
WHERE account_id IS NULL
   OR security_symbol IS NULL
   OR transaction_type IS NULL
   OR trade_date IS NULL;

-- 1.6 TRANSACTIONS: Orphan account references
-- Expected result: 0 transactions referencing an account that does not exist.
SELECT t.transaction_id, t.account_id
FROM transactions t
LEFT JOIN accounts a ON t.account_id = a.account_id
WHERE a.account_id IS NULL;

-- 1.7 TRANSACTIONS: Negative gross amounts
-- Expected result: 0 transactions with a negative gross amount.
SELECT transaction_id, transaction_type, gross_amount
FROM transactions
WHERE gross_amount < 0;

-- 1.8 COST BASIS: Duplicate basis record IDs
-- Expected result: 0 duplicate basis_record_id values.
-- Multiple basis records per transaction are legitimate tax-lot behavior.
SELECT basis_record_id, COUNT(*) AS duplicate_count
FROM cost_basis
GROUP BY basis_record_id
HAVING COUNT(*) > 1;

-- 1.9 COST BASIS: Missing critical fields
-- Expected result: 0 records with missing critical fields.
SELECT basis_record_id
FROM cost_basis
WHERE transaction_id IS NULL
   OR account_id IS NULL
   OR security_symbol IS NULL
   OR acquisition_date IS NULL
   OR sale_date IS NULL
   OR quantity_sold IS NULL
   OR proceeds IS NULL
   OR realized_gain_loss IS NULL;

-- 1.10 COST BASIS: Negative cost basis
-- Expected result: 0 records with negative cost basis.
SELECT basis_record_id, transaction_id, account_id, security_symbol, cost_basis
FROM cost_basis
WHERE cost_basis < 0;

-- 1.11 TAX FORMS: Duplicate tax-form IDs
-- Expected result: 0 duplicate tax_form_id values.
SELECT tax_form_id, COUNT(*) AS duplicate_count
FROM tax_forms
GROUP BY tax_form_id
HAVING COUNT(*) > 1;

-- 1.12 TAX FORMS: Missing critical fields
-- Expected result: 0 forms with missing critical identifying fields.
SELECT tax_form_id, account_id, form_type, tax_year
FROM tax_forms
WHERE account_id IS NULL
   OR form_type IS NULL
   OR tax_year IS NULL;

-- 1.13 TAX FORMS: Invalid tax years
-- Expected result: 0 forms outside the expected reporting-year range.
SELECT tax_form_id, account_id, form_type, tax_year
FROM tax_forms
WHERE tax_year < 1900
   OR tax_year > EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER;

-- 1.14 TAX FORMS: Negative reported values
-- Expected result: 0 records with negative values in fields expected to be non-negative.
SELECT tax_form_id, reported_proceeds, reported_cost_basis,
       reported_dividends, reported_interest, federal_tax_withheld
FROM tax_forms
WHERE reported_proceeds < 0
   OR reported_cost_basis < 0
   OR reported_dividends < 0
   OR reported_interest < 0
   OR federal_tax_withheld < 0;

-- 1.15 WITHHOLDING: Duplicate withholding IDs
-- Expected result: 0 duplicate withholding_id values.
SELECT withholding_id, COUNT(*) AS duplicate_count
FROM withholding
GROUP BY withholding_id
HAVING COUNT(*) > 1;

-- 1.16 WITHHOLDING: Missing critical fields
-- Expected result: 0 withholding records with missing critical fields.
SELECT withholding_id, account_id, transaction_id, withholding_type, income_type
FROM withholding
WHERE account_id IS NULL
   OR transaction_id IS NULL
   OR withholding_type IS NULL
   OR income_type IS NULL
   OR gross_payment IS NULL
   OR withholding_rate IS NULL
   OR withholding_amount IS NULL
   OR withholding_date IS NULL;

-- 1.17 WITHHOLDING: Negative withholding amounts
-- Expected result: 0 records with negative withholding amounts.
SELECT withholding_id, account_id, transaction_id, withholding_amount
FROM withholding
WHERE withholding_amount < 0;


-- ======================================================================================================
-- 2. TRANSACTION / COST-BASIS CONTROLS
-- ======================================================================================================

-- 2.1 SELL PROCEEDS: Transaction gross amount vs. cost-basis proceeds
-- Expected result: 0 discrepancies greater than $0.01.
SELECT
    t.transaction_id,
    t.account_id,
    t.gross_amount AS transaction_gross_amount,
    SUM(cb.proceeds) AS total_basis_proceeds,
    t.gross_amount - SUM(cb.proceeds) AS difference
FROM transactions t
JOIN cost_basis cb ON t.transaction_id = cb.transaction_id
WHERE t.transaction_type = 'SELL'
GROUP BY t.transaction_id, t.account_id, t.gross_amount
HAVING ABS(t.gross_amount - SUM(cb.proceeds)) > 0.01
ORDER BY ABS(t.gross_amount - SUM(cb.proceeds)) DESC;

-- 2.2 REALIZED GAIN/LOSS: Proceeds less cost basis
-- Expected result: 0 discrepancies greater than $0.01.
SELECT
    basis_record_id,
    transaction_id,
    proceeds,
    cost_basis,
    realized_gain_loss,
    proceeds - cost_basis AS calculated_gain_loss,
    realized_gain_loss - (proceeds - cost_basis) AS difference
FROM cost_basis
WHERE ABS(realized_gain_loss - (proceeds - cost_basis)) > 0.01
ORDER BY ABS(realized_gain_loss - (proceeds - cost_basis)) DESC;

-- 2.3 ADJUSTED GAIN/LOSS: Realized gain/loss plus wash-sale adjustment
-- Expected result: 0 discrepancies greater than $0.01.
SELECT
    basis_record_id,
    transaction_id,
    realized_gain_loss,
    wash_sale_adjustment,
    adjusted_gain_loss,
    realized_gain_loss + wash_sale_adjustment AS calculated_adjusted_gain_loss,
    adjusted_gain_loss - (realized_gain_loss + wash_sale_adjustment) AS difference
FROM cost_basis
WHERE ABS(adjusted_gain_loss - (realized_gain_loss + wash_sale_adjustment)) > 0.01
ORDER BY ABS(adjusted_gain_loss - (realized_gain_loss + wash_sale_adjustment)) DESC;

-- 2.4 TRANSACTION GROSS AMOUNT: Quantity multiplied by price
-- Expected result: 0 discrepancies greater than $0.01 for SELL transactions.
SELECT
    transaction_id,
    account_id,
    security_symbol,
    quantity,
    price,
    gross_amount,
    quantity * price AS calculated_gross_amount,
    gross_amount - (quantity * price) AS difference
FROM transactions
WHERE transaction_type = 'SELL'
  AND ABS(gross_amount - (quantity * price)) > 0.01
ORDER BY ABS(gross_amount - (quantity * price)) DESC;


-- ======================================================================================================
-- 3. TAX-REPORTING CONTROLS
-- ======================================================================================================

-- 3.1 1099-B PROCEEDS: Operational sales vs. reported proceeds
-- Expected result: 0 unexplained differences greater than $0.01.
-- transaction_proceeds is a calculated value, not a physical table column.
SELECT
    t.account_id,
    SUM(t.gross_amount) AS transaction_proceeds,
    f.reported_proceeds,
    SUM(t.gross_amount) - f.reported_proceeds AS proceeds_difference
FROM transactions t
JOIN tax_forms f ON t.account_id = f.account_id
WHERE t.transaction_type = 'SELL'
  AND f.form_type = '1099-B'
GROUP BY t.account_id, f.reported_proceeds
HAVING ABS(SUM(t.gross_amount) - f.reported_proceeds) > 0.01
ORDER BY ABS(SUM(t.gross_amount) - f.reported_proceeds) DESC;

-- 3.2 1099-B COMPLETENESS: SELL activity with no 1099-B
-- Expected result: 0 accounts with reportable SELL activity and no 1099-B.
SELECT
    t.account_id,
    SUM(t.gross_amount) AS total_sell_proceeds
FROM transactions t
LEFT JOIN tax_forms f
    ON t.account_id = f.account_id
   AND f.form_type = '1099-B'
WHERE t.transaction_type = 'SELL'
  AND f.tax_form_id IS NULL
GROUP BY t.account_id
ORDER BY total_sell_proceeds DESC;

-- 3.3 1099-B EXCEPTION CLASSIFICATION
-- Expected result: Rounding differences are separated from substantive exceptions.
-- Exact-dollar patterns observed during investigation remain visible for triage.
WITH reconciliation AS (
    SELECT
        t.account_id,
        SUM(t.gross_amount) AS transaction_proceeds,
        f.reported_proceeds,
        SUM(t.gross_amount) - f.reported_proceeds AS proceeds_difference
    FROM transactions t
    JOIN tax_forms f ON t.account_id = f.account_id
    WHERE t.transaction_type = 'SELL'
      AND f.form_type = '1099-B'
    GROUP BY t.account_id, f.reported_proceeds
    HAVING ABS(SUM(t.gross_amount) - f.reported_proceeds) > 0.01
)
SELECT
    account_id,
    transaction_proceeds,
    reported_proceeds,
    proceeds_difference,
    CASE
        WHEN ABS(proceeds_difference) IN (50, 250, 500, 1000)
            THEN 'Exact-dollar adjustment'
        ELSE 'Other difference'
    END AS exception_category
FROM reconciliation
ORDER BY ABS(proceeds_difference) DESC;


-- ======================================================================================================
-- 4. WITHHOLDING CONTROLS
-- ======================================================================================================

-- 4.1 WITHHOLDING CALCULATION
-- Expected result: 0 discrepancies greater than $0.01.
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
WHERE ABS(withholding_amount - (gross_payment * withholding_rate)) > 0.01
ORDER BY ABS(withholding_amount - (gross_payment * withholding_rate)) DESC;

-- 4.2 NRA WITHHOLDING: NRA withholding vs. 1042-S
-- Expected result: 0 unexplained differences greater than $0.01.
WITH nra_summary AS (
    SELECT account_id, SUM(withholding_amount) AS nra_withholding
    FROM withholding
    WHERE withholding_type = 'NRA_WITHHOLDING'
    GROUP BY account_id
),
form_summary AS (
    SELECT account_id, SUM(federal_tax_withheld) AS reported_1042s_withholding
    FROM tax_forms
    WHERE form_type = '1042-S'
    GROUP BY account_id
)
SELECT
    n.account_id,
    n.nra_withholding,
    COALESCE(f.reported_1042s_withholding, 0) AS reported_1042s_withholding,
    n.nra_withholding - COALESCE(f.reported_1042s_withholding, 0) AS difference
FROM nra_summary n
LEFT JOIN form_summary f ON n.account_id = f.account_id
WHERE ABS(n.nra_withholding - COALESCE(f.reported_1042s_withholding, 0)) > 0.01
ORDER BY ABS(n.nra_withholding - COALESCE(f.reported_1042s_withholding, 0)) DESC;

-- 4.3 BACKUP WITHHOLDING: Sale proceeds with no 1099-B
-- Expected result: 0 accounts with backup withholding on sale proceeds but no 1099-B.
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


-- ======================================================================================================
-- 5. EXCEPTION SUMMARY CONTROLS
-- ======================================================================================================

-- 5.1 COST-BASIS EXCEPTION SUMMARY
-- Expected result: Summarize exception count and affected activity.
SELECT
    COUNT(*) AS exception_record_count,
    COUNT(DISTINCT transaction_id) AS affected_transaction_count,
    COUNT(DISTINCT account_id) AS affected_account_count
FROM cost_basis
WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01;

-- 5.2 WITHHOLDING EXCEPTION SUMMARY
-- Expected result: Quantify withholding calculation exceptions and dollar impact.
SELECT
    COUNT(*) AS exception_count,
    SUM(ABS(withholding_amount - (gross_payment * withholding_rate))) AS total_absolute_difference,
    MAX(ABS(withholding_amount - (gross_payment * withholding_rate))) AS largest_absolute_difference
FROM withholding
WHERE ABS(withholding_amount - (gross_payment * withholding_rate)) > 0.01;


-- ======================================================================================================
-- END OF FINAL CONTROL LIBRARY
-- ======================================================================================================
