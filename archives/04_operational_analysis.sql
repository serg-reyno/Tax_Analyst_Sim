-- ====================================================================================================== 
-- OPERATIONAL ANALYSIS 
-- ======================================================================================================
-- ======================================================================================================
-- TAX FORM RECONCILIATION
-- ======================================================================================================

-- Control 1: Review 1099-B records
-- Expected result: Identify the 1099-B records available for reconciliation.
-- These forms should contain reported proceeds and cost basis for reportable sales.

SELECT
    tax_form_id,
    account_id,
    form_type,
    tax_year,
    reported_proceeds,
    reported_cost_basis,
    reported_gain_loss,
    status
FROM tax_forms
WHERE form_type = '1099-B';

-- ======================================================================================================
-- 1099-B PROCEEDS RECONCILIATION
-- ======================================================================================================
-- Reconcile total SELL transaction proceeds to reported 1099-B proceeds by account.
-- Expected result: Accounts with differences should be investigated as reconciliation exceptions.

SELECT
    t.account_id,
    SUM(t.gross_amount) AS transaction_proceeds,
    f.reported_proceeds,
    SUM(t.gross_amount) - f.reported_proceeds AS proceeds_difference
FROM transactions t
JOIN tax_forms f
    ON t.account_id = f.account_id
WHERE t.transaction_type = 'SELL'
  AND f.form_type = '1099-B'
GROUP BY
    t.account_id,
    f.reported_proceeds
HAVING SUM(t.gross_amount) <> f.reported_proceeds
ORDER BY ABS(SUM(t.gross_amount) - f.reported_proceeds) DESC;

-- ======================================================================================================
-- 1099-B RECONCILIATION: DIFFERENCE SIZE ANALYSIS
-- ======================================================================================================
-- Classify reconciliation differences by magnitude.
-- Expected result: Small differences near $0.01 may represent rounding;
-- exact-dollar and larger differences should be investigated separately.

WITH reconciliation AS (
    SELECT
        t.account_id,
        SUM(t.gross_amount) AS transaction_proceeds,
        f.reported_proceeds,
        SUM(t.gross_amount) - f.reported_proceeds AS proceeds_difference
    FROM transactions t
    JOIN tax_forms f
        ON t.account_id = f.account_id
    WHERE t.transaction_type = 'SELL'
      AND f.form_type = '1099-B'
    GROUP BY
        t.account_id,
        f.reported_proceeds
    HAVING SUM(t.gross_amount) <> f.reported_proceeds
)

SELECT
    CASE
        WHEN ABS(proceeds_difference) <= 0.01
            THEN 'Rounding (<= $0.01)'
        WHEN ABS(proceeds_difference) IN (50, 250, 500, 1000)
            THEN 'Exact-dollar adjustment'
        ELSE 'Other difference'
    END AS difference_category,
    COUNT(*) AS exception_count
FROM reconciliation
GROUP BY
    CASE
        WHEN ABS(proceeds_difference) <= 0.01
            THEN 'Rounding (<= $0.01)'
        WHEN ABS(proceeds_difference) IN (50, 250, 500, 1000)
            THEN 'Exact-dollar adjustment'
        ELSE 'Other difference'
    END
ORDER BY exception_count DESC;

-- ======================================================================================================
-- 1099-B RECONCILIATION: REVIEW OTHER DIFFERENCES
-- ======================================================================================================
-- Expected result: Identify the account-level discrepancies that do not fall into
-- rounding or known exact-dollar difference patterns.

WITH reconciliation AS (
    SELECT
        t.account_id,
        SUM(t.gross_amount) AS transaction_proceeds,
        f.reported_proceeds,
        SUM(t.gross_amount) - f.reported_proceeds AS proceeds_difference
    FROM transactions t
    JOIN tax_forms f
        ON t.account_id = f.account_id
    WHERE t.transaction_type = 'SELL'
      AND f.form_type = '1099-B'
    GROUP BY
        t.account_id,
        f.reported_proceeds
    HAVING SUM(t.gross_amount) <> f.reported_proceeds
)

SELECT *
FROM reconciliation
WHERE ABS(proceeds_difference) > 0.01
  AND ABS(proceeds_difference) NOT IN (50, 250, 500, 1000)
ORDER BY ABS(proceeds_difference) DESC;

-- Investigation: Review SELL transactions for ACC000210
-- Expected result: Identify every underlying sale contributing to the
-- calculated transaction proceeds used in the 1099-B reconciliation.

SELECT
    transaction_id,
    security_symbol,
    security_type,
    transaction_type,
    trade_date,
    quantity,
    price,
    gross_amount
FROM transactions
WHERE account_id = 'ACC000210'
  AND transaction_type = 'SELL'
ORDER BY trade_date;

-- Investigation: Trace ACC000210 SELL transactions into cost basis
-- Expected result: Identify the cost-basis/tax-lot records associated
-- with each sale and compare their proceeds to the transaction gross amounts.

SELECT
    t.transaction_id,
    t.security_symbol,
    t.trade_date,
    t.gross_amount,
    cb.basis_record_id,
    cb.acquisition_date,
    cb.quantity_sold,
    cb.cost_basis,
    cb.proceeds,
    cb.realized_gain_loss,
    cb.adjusted_gain_loss
FROM transactions t
LEFT JOIN cost_basis cb
    ON t.transaction_id = cb.transaction_id
WHERE t.account_id = 'ACC000210'
  AND t.transaction_type = 'SELL'
ORDER BY t.trade_date, cb.basis_record_id;

-- Investigation: Review tax-form reporting for ACC000210
-- Expected result: Identify the 1099-B record and reported proceeds
-- underlying the reconciliation difference.

SELECT
    tax_form_id,
    account_id,
    form_type,
    tax_year,
    reported_proceeds,
    reported_cost_basis,
    reported_gain_loss,
    status
FROM tax_forms
WHERE account_id = 'ACC000210'
  AND form_type = '1099-B';

  -- Investigation: Review all activity for ACC000210
-- Expected result: Identify whether any non-SELL activity or additional
-- transaction activity could explain the 1099-B reported proceeds.

SELECT
    transaction_id,
    security_symbol,
    transaction_type,
    trade_date,
    quantity,
    price,
    gross_amount,
    description
FROM transactions
WHERE account_id = 'ACC000210'
ORDER BY trade_date, transaction_id;
-- Investigation: Validate internal 1099-B gain/loss arithmetic
-- Expected result: Reported gain/loss should reconcile to reported
-- proceeds minus reported cost basis, subject to the dataset's
-- intended treatment of adjustments.

SELECT
    tax_form_id,
    reported_proceeds,
    reported_cost_basis,
    reported_gain_loss,
    reported_proceeds - reported_cost_basis AS calculated_gain_loss,
    reported_gain_loss - (reported_proceeds - reported_cost_basis) AS difference
FROM tax_forms
WHERE account_id = 'ACC000210'
  AND form_type = '1099-B';

  -- Investigation: Review SELL transactions for ACC000638
-- Expected result: Identify every underlying sale contributing to
-- the calculated proceeds used in the 1099-B reconciliation.

SELECT
    transaction_id,
    security_symbol,
    security_type,
    transaction_type,
    trade_date,
    quantity,
    price,
    gross_amount
FROM transactions
WHERE account_id = 'ACC000638'
  AND transaction_type = 'SELL'
ORDER BY trade_date;

-- Investigation: Trace ACC000638 SELL transactions into cost basis
-- Expected result: Cost-basis proceeds should reconcile to the
-- corresponding transaction gross amounts.

SELECT
    t.transaction_id,
    t.security_symbol,
    t.trade_date,
    t.gross_amount,
    cb.basis_record_id,
    cb.acquisition_date,
    cb.quantity_sold,
    cb.cost_basis,
    cb.proceeds,
    cb.realized_gain_loss,
    cb.adjusted_gain_loss
FROM transactions t
LEFT JOIN cost_basis cb
    ON t.transaction_id = cb.transaction_id
WHERE t.account_id = 'ACC000638'
  AND t.transaction_type = 'SELL'
ORDER BY t.trade_date, cb.basis_record_id;

-- Investigation: Review 1099-B reporting for ACC000638
-- Expected result: Compare reported proceeds and cost basis to the
-- underlying transaction/cost-basis totals.

SELECT
    tax_form_id,
    account_id,
    form_type,
    tax_year,
    reported_proceeds,
    reported_cost_basis,
    reported_gain_loss,
    status
FROM tax_forms
WHERE account_id = 'ACC000638'
  AND form_type = '1099-B';

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
-- WITHHOLDING CALCULATION EXCEPTION SUMMARY
-- ======================================================================================================
-- Expected result: Quantify the number and dollar impact of withholding
-- calculation exceptions. Small dollar differences should still be
-- evaluated relative to the expected withholding amount.

SELECT
    COUNT(*) AS exception_count,
    SUM(ABS(withholding_amount - (gross_payment * withholding_rate))) AS total_absolute_difference,
    MAX(ABS(withholding_amount - (gross_payment * withholding_rate))) AS largest_absolute_difference
FROM withholding
WHERE ABS(
    withholding_amount - (gross_payment * withholding_rate)
) > 0.01;

-- Profiling: Review withholding calculation exceptions by withholding type
-- Expected result: Identify whether calculation exceptions are concentrated
-- in a particular withholding process.

SELECT
    withholding_type,
    COUNT(*) AS exception_count,
    SUM(ABS(withholding_amount - (gross_payment * withholding_rate))) AS total_absolute_difference
FROM withholding
WHERE ABS(
    withholding_amount - (gross_payment * withholding_rate)
) > 0.01
GROUP BY withholding_type
ORDER BY exception_count DESC;

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

-- Investigation: Review backup withholding sale-proceeds records
-- for accounts with no reported 1099-B federal withholding.
-- Expected result: Determine whether the withholding records themselves
-- contain valid transaction, payment, rate, and documentation information.

SELECT
    w.account_id,
    w.withholding_id,
    w.transaction_id,
    w.gross_payment,
    w.withholding_rate,
    w.withholding_amount,
    w.withholding_date,
    w.documentation_status
FROM withholding w
WHERE w.withholding_type = 'BACKUP_WITHHOLDING'
  AND w.income_type = 'SALE_PROCEEDS'
  AND w.account_id IN (
      'ACC000345',
      'ACC000288',
      'ACC000121',
      'ACC000435',
      'ACC000359',
      'ACC000550',
      'ACC000461',
      'ACC000561',
      'ACC000268'
  )
ORDER BY w.account_id, w.withholding_date;

-- Investigation: Review 1099-B reporting for accounts with
-- backup withholding on sale proceeds.
-- Expected result: Determine whether federal withholding is recorded
-- as zero, NULL, or another amount on the corresponding tax forms.

SELECT
    tax_form_id,
    account_id,
    form_type,
    tax_year,
    reported_proceeds,
    reported_cost_basis,
    reported_gain_loss,
    federal_tax_withheld,
    status
FROM tax_forms
WHERE form_type = '1099-B'
  AND account_id IN (
      'ACC000345',
      'ACC000288',
      'ACC000121',
      'ACC000435',
      'ACC000359',
      'ACC000550',
      'ACC000461',
      'ACC000561',
      'ACC000268'
  )
ORDER BY account_id;

-- Investigation: Trace backup withholding from transactions to tax form
-- for ACC000345.
--
-- Expected result: Determine whether the transaction, withholding,
-- and 1099-B reporting records follow a consistent lineage.

SELECT
    t.transaction_id,
    t.security_symbol,
    t.transaction_type,
    t.trade_date,
    t.gross_amount,
    w.withholding_id,
    w.gross_payment,
    w.withholding_rate,
    w.withholding_amount,
    w.documentation_status
FROM transactions t
JOIN withholding w
    ON t.transaction_id = w.transaction_id
WHERE t.account_id = 'ACC000345'
  AND t.transaction_type = 'SELL'
ORDER BY t.trade_date;

-- Investigation: Review the 1099-B reporting record for ACC000345.
-- Expected result: Compare reported proceeds and federal withholding
-- to the underlying transaction and withholding activity.

SELECT
    tax_form_id,
    account_id,
    form_type,
    tax_year,
    reported_proceeds,
    reported_cost_basis,
    reported_gain_loss,
    federal_tax_withheld,
    status
FROM tax_forms
WHERE account_id = 'ACC000345'
  AND form_type = '1099-B';

-- Investigation: Review all tax forms associated with ACC000345.
-- Expected result: Determine whether the account has another tax form
-- that may contain the sale-proceeds reporting or whether the expected
-- 1099-B record is completely missing.

SELECT
    tax_form_id,
    account_id,
    form_type,
    tax_year,
    reported_proceeds,
    reported_cost_basis,
    reported_gain_loss,
    federal_tax_withheld,
    status
FROM tax_forms
WHERE account_id = 'ACC000345'
ORDER BY tax_year, form_type;

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