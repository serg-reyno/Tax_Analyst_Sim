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

-- Reconciliation: Review transaction and cost-basis relationship
-- Expected result: Identify the transaction date and related cost-basis records
-- to understand why one SELL transaction has multiple basis records.

SELECT
    t.transaction_id,
    t.account_id,
    t.security_symbol,
    t.transaction_type,
    t.trade_date,
    t.gross_amount,
    cb.basis_record_id,
    cb.cost_basis,
    cb.realized_gain_loss
FROM transactions t
JOIN cost_basis cb
    ON t.transaction_id = cb.transaction_id
WHERE t.transaction_id = 'TXN00000034'
ORDER BY cb.basis_record_id;

-- Reconciliation: Check uniqueness of basis record IDs
-- Expected result: 0 records
-- Each basis record should have a unique basis_record_id

SELECT
    basis_record_id,
    COUNT(*) AS duplicate_count
FROM cost_basis
GROUP BY basis_record_id
HAVING COUNT(*) > 1;

-- Reconciliation: Review transaction and cost-basis relationship
-- Expected result: Identify the transaction date and related cost-basis records
-- to understand why one SELL transaction has multiple basis records.

SELECT
    t.transaction_id,
    t.account_id,
    t.security_symbol,
    t.transaction_type,
    t.trade_date,
    t.gross_amount,
    cb.basis_record_id,
    cb.cost_basis,
    cb.realized_gain_loss
FROM transactions t
JOIN cost_basis cb
    ON t.transaction_id = cb.transaction_id
WHERE t.transaction_id = 'TXN00000034'
ORDER BY cb.basis_record_id;

SELECT
    t.transaction_id,
    t.trade_date,
    cb.basis_record_id,
    cb.sale_date,
    cb.cost_basis,
    cb.realized_gain_loss
FROM transactions t
JOIN cost_basis cb
    ON t.transaction_id = cb.transaction_id
WHERE t.transaction_id = 'TXN00000034'
ORDER BY cb.basis_record_id;

SELECT
    transaction_id,
    account_id,
    security_symbol,
    transaction_type,
    trade_date,
    gross_amount
FROM transactions
WHERE account_id = 'ACC000004'
  AND security_symbol = 'HZN'
  AND trade_date <= '2024-12-26'
ORDER BY trade_date;

-- Reconciliation: Investigate tax-lot allocation within a SELL transaction
-- Expected result: Each basis record should represent a distinct tax lot or
-- basis allocation, with its own acquisition date, quantity, basis, proceeds,
-- and gain/loss information.

SELECT
    basis_record_id,
    transaction_id,
    account_id,
    security_symbol,
    acquisition_date,
    sale_date,
    quantity_sold,
    cost_basis,
    proceeds,
    realized_gain_loss,
    wash_sale_adjustment,
    adjusted_gain_loss,
    covered_status,
    holding_period
FROM cost_basis
WHERE transaction_id = 'TXN00000034'
ORDER BY acquisition_date;

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

-- Reconciliation: Investigate gain/loss calculation exceptions
-- Expected result: Identify the factors causing the 14 gain/loss discrepancies,
-- including wash-sale adjustments, adjusted gain/loss, transaction details,
-- and tax-lot characteristics.

SELECT
    cb.basis_record_id,
    cb.transaction_id,
    cb.account_id,
    cb.security_symbol,
    cb.acquisition_date,
    cb.sale_date,
    cb.quantity_sold,
    cb.cost_basis,
    cb.proceeds,
    cb.realized_gain_loss,
    cb.wash_sale_adjustment,
    cb.adjusted_gain_loss,
    cb.covered_status,
    cb.holding_period,
    t.transaction_type,
    t.gross_amount,
    (cb.proceeds - cb.cost_basis) AS calculated_gain_loss,
    cb.realized_gain_loss - (cb.proceeds - cb.cost_basis) AS difference
FROM cost_basis cb
JOIN transactions t
    ON cb.transaction_id = t.transaction_id
WHERE cb.basis_record_id IN (
    'BAS00000114',
    'BAS00000135',
    'BAS00000310',
    'BAS00000619',
    'BAS00000753',
    'BAS00000780',
    'BAS00000827',
    'BAS00001224',
    'BAS00001384',
    'BAS00001415',
    'BAS00001619',
    'BAS00001966',
    'BAS00002506',
    'BAS00002695'
)
ORDER BY cb.basis_record_id;

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

-- Reconciliation: Investigate gain/loss exception
-- Expected result: Identify related transactions that may explain
-- the difference between realized and adjusted gain/loss.

SELECT
    transaction_id,
    account_id,
    security_symbol,
    transaction_type,
    trade_date,
    gross_amount
FROM transactions
WHERE account_id = 'ACC000041'
  AND security_symbol = 'LMR'
ORDER BY trade_date;

-- Reconciliation: Compare cost basis to the underlying acquisition transaction
-- Expected result: The acquisition transaction should correspond to the
-- cost-basis acquisition date and provide a reasonable basis for the tax lot.

SELECT
    cb.basis_record_id,
    cb.transaction_id AS sale_transaction_id,
    cb.account_id,
    cb.security_symbol,
    cb.acquisition_date,
    cb.quantity_sold,
    cb.cost_basis,
    cb.proceeds,
    cb.realized_gain_loss,
    cb.adjusted_gain_loss,
    t.transaction_id AS acquisition_transaction_id,
    t.trade_date AS acquisition_trade_date,
    t.gross_amount AS acquisition_gross_amount
FROM cost_basis cb
JOIN transactions t
    ON cb.account_id = t.account_id
   AND cb.security_symbol = t.security_symbol
   AND cb.acquisition_date = t.trade_date
WHERE cb.basis_record_id = 'BAS00000135';


-- Reconciliation: Validate adjusted gain/loss against proceeds and cost basis
-- Expected result: 0 discrepancies
-- Adjusted gain/loss should generally equal proceeds minus cost basis,
-- unless another documented adjustment affects the calculation.

SELECT
    basis_record_id,
    proceeds,
    cost_basis,
    adjusted_gain_loss,
    proceeds - cost_basis AS calculated_adjusted_gain_loss,
    adjusted_gain_loss - (proceeds - cost_basis) AS difference
FROM cost_basis
WHERE ABS(
    adjusted_gain_loss - (proceeds - cost_basis)
) > 0.01;

-- Reconciliation: Summarize adjusted gain/loss exceptions
-- Expected result: Exception count should identify the population requiring investigation
-- rather than requiring manual review of every individual record.

SELECT
    COUNT(*) AS total_cost_basis_records,
    COUNT(*) FILTER (
        WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01
    ) AS adjusted_gain_loss_exceptions
FROM cost_basis;

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

-- Profiling: Review total cost-basis records by holding period
-- Expected result: Establish the population baseline for short-term vs. long-term records
-- so exception rates can be compared accurately.

SELECT
    holding_period,
    COUNT(*) AS total_records
FROM cost_basis
GROUP BY holding_period
ORDER BY total_records DESC;

-- Profiling: Review total cost-basis records by covered status
-- Expected result: Establish the population baseline for covered vs. non-covered records
-- so exception rates can be compared accurately.

SELECT
    covered_status,
    COUNT(*) AS total_records
FROM cost_basis
GROUP BY covered_status
ORDER BY total_records DESC;

-- Profiling: Review total cost-basis records by security type
-- Expected result: Establish the total population within each security type
-- for calculating exception rates.

SELECT
    security_type,
    COUNT(*) AS total_records
FROM cost_basis
GROUP BY security_type
ORDER BY total_records DESC;


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

-- Exception Profiling: Identify negative-basis records within the
-- adjusted gain/loss exception population.
-- Expected result: Identify how many of the 65 reconciliation exceptions
-- are also caused by negative cost basis.

SELECT COUNT(*) AS negative_basis_exceptions
FROM cost_basis
WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01
  AND cost_basis < 0;

-- Exception Profiling: Identify NULL-basis records within the
-- adjusted gain/loss exception population.
-- Expected result: Identify how many of the 65 reconciliation exceptions
-- also have missing cost basis.

SELECT COUNT(*) AS null_basis_exceptions
FROM cost_basis
WHERE ABS(adjusted_gain_loss - (proceeds - cost_basis)) > 0.01
  AND cost_basis IS NULL;

-- Profiling: Summarize the adjusted gain/loss exception population
-- Expected result: 65 exception records, with distinct transaction and account
-- counts showing the true scope of affected activity.

SELECT
    COUNT(*) AS exception_record_count,
    COUNT(DISTINCT transaction_id) AS affected_transaction_count,
    COUNT(DISTINCT account_id) AS affected_account_count
FROM cost_basis
WHERE ABS(
    adjusted_gain_loss - (proceeds - cost_basis)
) > 0.01;
