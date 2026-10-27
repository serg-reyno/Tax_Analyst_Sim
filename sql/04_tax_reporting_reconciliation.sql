-- Tax Analyst Sim | 04_tax_reporting_reconciliation
-- Purpose: Compare operational sales to customer tax reporting.
-- Files 02-06 are SELECT-only and use the existing imported tables.
-- Expected results describe a clean baseline; corrupted data can return exceptions.
-- Scope: Original reporting comparisons assume one reporting year and one applicable form
-- per account/form type. Resolve duplicate forms and statuses before relying on totals.
-- Federal reporting comparisons require category mapping; do not treat all withholding as federal.

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
