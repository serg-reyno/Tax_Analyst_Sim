-- Tax Analyst Sim | 06_exception_analysis
-- Purpose: Summarize discrepancies, affected activity and investigation priorities.
-- Files 02-06 are SELECT-only and use the existing imported tables.
-- Expected results describe a clean baseline; corrupted data can return exceptions.
-- Scope: Original reporting comparisons assume one reporting year and one applicable form
-- per account/form type. Resolve duplicate forms and statuses before relying on totals.
-- Federal reporting comparisons require category mapping; do not treat all withholding as federal.

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Reconciliation: Summarize adjusted gain/loss exceptions
-- Expected result: Exception count should identify the population requiring investigation
-- rather than requiring manual review of every individual record.

SELECT
    COUNT(*) AS total_cost_basis_records,
    COUNT(*) FILTER (
        WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01
    ) AS adjusted_gain_loss_exceptions
FROM cost_basis;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Reconciliation: Analyze adjusted gain/loss exceptions by holding period
-- Expected result: Identify whether exceptions are concentrated within
-- short-term or long-term transactions.

SELECT
    holding_period,
    COUNT(*) AS exception_count
FROM cost_basis
WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01
GROUP BY holding_period
ORDER BY exception_count DESC;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Reconciliation: Analyze adjusted gain/loss exceptions by covered status
-- Expected result: Identify whether exceptions are concentrated within
-- covered or non-covered basis records.

SELECT
    covered_status,
    COUNT(*) AS exception_count
FROM cost_basis
WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01
GROUP BY covered_status
ORDER BY exception_count DESC;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Profiling: Review total cost-basis records by holding period
-- Expected result: Establish the population baseline for short-term vs. long-term records
-- so exception rates can be compared accurately.

SELECT
    holding_period,
    COUNT(*) AS total_records
FROM cost_basis
GROUP BY holding_period
ORDER BY total_records DESC;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Profiling: Review total cost-basis records by covered status
-- Expected result: Establish the population baseline for covered vs. non-covered records
-- so exception rates can be compared accurately.

SELECT
    covered_status,
    COUNT(*) AS total_records
FROM cost_basis
GROUP BY covered_status
ORDER BY total_records DESC;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Profiling: Review total cost-basis records by security type
-- Expected result: Establish the total population within each security type
-- for calculating exception rates.

SELECT
    security_type,
    COUNT(*) AS total_records
FROM cost_basis
GROUP BY security_type
ORDER BY total_records DESC;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.


-- Profiling: Review adjusted gain/loss exceptions by security type
-- Expected result: Identify whether reconciliation exceptions are disproportionately
-- concentrated within a particular security type.

SELECT
    security_type,
    COUNT(*) AS exception_count
FROM cost_basis
WHERE ABS(
    adjusted_gain_loss - (proceeds - cost_basis)
) > 0.01
GROUP BY security_type
ORDER BY exception_count DESC;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Profiling: Review adjusted gain/loss exceptions by transaction type
-- Expected result: Exceptions should be associated with SELL transactions,
-- since realized and adjusted gain/loss are generated from security sales.

SELECT
    t.transaction_type,
    COUNT(*) AS exception_count
FROM cost_basis cb
JOIN transactions t
    ON cb.transaction_id = t.transaction_id
WHERE ABS(
    cb.adjusted_gain_loss - (cb.proceeds - cb.cost_basis)
) > 0.01
GROUP BY t.transaction_type
ORDER BY exception_count DESC;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Profiling: Compare dollar-value characteristics of exception records
-- Expected result: Identify whether exceptions have noticeably different
-- proceeds, cost basis, or quantity characteristics than the overall population.

SELECT
    COUNT(*) AS exception_count,
    MIN(proceeds) AS minimum_proceeds,
    MAX(proceeds) AS maximum_proceeds,
    AVG(proceeds) AS average_proceeds,
    MIN(cost_basis) AS minimum_cost_basis,
    MAX(cost_basis) AS maximum_cost_basis,
    AVG(cost_basis) AS average_cost_basis,
    MIN(quantity_sold) AS minimum_quantity_sold,
    MAX(quantity_sold) AS maximum_quantity_sold,
    AVG(quantity_sold) AS average_quantity_sold
FROM cost_basis
WHERE ABS(
    adjusted_gain_loss - (proceeds - cost_basis)
) > 0.01;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Exception Profiling: Identify negative-basis records within the
-- adjusted gain/loss exception population.
-- Expected result: Identify how many diagnostic candidates
-- are also caused by negative cost basis.

SELECT COUNT(*) AS negative_basis_exceptions
FROM cost_basis
WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01
  AND cost_basis < 0;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Exception Profiling: Identify NULL-basis records within the
-- full cost-basis population (NULL values cannot pass an arithmetic filter).
-- Expected result: Identify how many diagnostic candidates
-- have missing cost basis, separately from arithmetic differences.

SELECT COUNT(*) AS null_basis_exceptions
FROM cost_basis
WHERE cost_basis IS NULL;

-- Diagnostic population: adjusted gain/loss minus unadjusted proceeds less basis.
-- Nonzero values may reflect legitimate adjustments; counts are review candidates, not confirmed errors.

-- Profiling: Summarize the adjusted gain/loss exception population
-- Expected result: Dataset-dependent review-candidate count, with distinct transaction and account
-- counts showing the true scope of affected activity.

SELECT
    COUNT(*) AS exception_record_count,
    COUNT(DISTINCT transaction_id) AS affected_transaction_count,
    COUNT(DISTINCT account_id) AS affected_account_count
FROM cost_basis
WHERE ABS(
    adjusted_gain_loss - (proceeds - cost_basis)
) > 0.01;

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
