-- Tax Analyst Sim | 03_transaction_cost_basis_reconciliation
-- Purpose: Reconcile sale transactions to tax lots and test gain/loss arithmetic.
-- Files 02-06 are SELECT-only and use the existing imported tables.
-- Expected results describe a clean baseline; corrupted data can return exceptions.

-- ======================================================================================================
-- TRANSACTIONS ↔ COST BASIS RECONCILIATION
-- ======================================================================================================

-- Reconciliation: Investigate transactions with multiple cost basis records
-- Expected result: Multiple records may be legitimate if one transaction can have multiple basis records/lots.
-- The purpose of this query is to understand the relationship before treating duplicates as errors.

SELECT
    t.transaction_id,
    t.account_id,
    t.security_symbol,
    t.transaction_type,
    t.gross_amount,
    cb.basis_record_id,
    cb.cost_basis,
    cb.realized_gain_loss
FROM transactions t
JOIN cost_basis cb
    ON t.transaction_id = cb.transaction_id
WHERE t.transaction_id IN (
    SELECT transaction_id
    FROM cost_basis
    GROUP BY transaction_id
    HAVING COUNT(*) > 1
)
ORDER BY t.transaction_id, cb.basis_record_id
LIMIT 50;

-- Reconciliation: Compare total cost-basis proceeds to transaction gross amount
-- Expected result: 0 discrepancies
-- The sum of proceeds across all basis records for a transaction should equal
-- the gross amount recorded for the corresponding SELL transaction.

SELECT
    t.transaction_id,
    t.gross_amount,
    SUM(cb.proceeds) AS total_basis_proceeds,
    t.gross_amount - SUM(cb.proceeds) AS difference
FROM transactions t
JOIN cost_basis cb
    ON t.transaction_id = cb.transaction_id
WHERE t.transaction_type = 'SELL'
GROUP BY
    t.transaction_id,
    t.gross_amount
HAVING ABS(t.gross_amount - SUM(cb.proceeds)) > 0.01;

-- Reconciliation: Validate realized gain/loss calculation
-- Expected result: 0 discrepancies
-- Realized gain/loss should equal proceeds minus cost basis for each basis record.

SELECT
    basis_record_id,
    proceeds,
    cost_basis,
    realized_gain_loss,
    proceeds - cost_basis AS calculated_gain_loss,
    realized_gain_loss - (proceeds - cost_basis) AS difference
FROM cost_basis
WHERE ABS(realized_gain_loss - (proceeds - cost_basis)) > 0.01;

-- Reconciliation: Validate adjusted gain/loss calculation
-- Expected result: 0 discrepancies
-- Adjusted gain/loss should reconcile to realized gain/loss and the wash-sale adjustment.

SELECT
    basis_record_id,
    realized_gain_loss,
    wash_sale_adjustment,
    adjusted_gain_loss,
    realized_gain_loss + wash_sale_adjustment AS calculated_adjusted_gain_loss,
    adjusted_gain_loss
        - (realized_gain_loss + wash_sale_adjustment) AS difference
FROM cost_basis
WHERE ABS(
    adjusted_gain_loss
    - (realized_gain_loss + wash_sale_adjustment)
) > 0.01;

-- Reconciliation: Validate SELL transaction gross amount
-- Expected result: 0 discrepancies, allowing for minor rounding.
-- Gross amount should generally equal quantity multiplied by price.

SELECT
    transaction_id,
    quantity,
    price,
    gross_amount,
    quantity * price AS calculated_gross_amount,
    gross_amount - (quantity * price) AS difference
FROM transactions
WHERE transaction_type = 'SELL'
  AND ABS(gross_amount - (quantity * price)) > 0.01;
