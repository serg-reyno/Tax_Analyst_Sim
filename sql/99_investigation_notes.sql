-- Tax Analyst Sim | 99_investigation_notes
-- Purpose: Trace specific historical exceptions; sample IDs may change with a new dataset.
-- Files 02-06 are SELECT-only and use the existing imported tables.
-- Expected results describe a clean baseline; corrupted data can return exceptions.

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

-- Expected result: Review the sample sale date or earlier acquisition activity.

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

-- Expected result: Review the sample sale date or earlier acquisition activity.

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
-- Expected result: Diagnostic differences may include valid wash-sale adjustments.
-- Compare to File 03 adjusted gain/loss arithmetic before calling a difference an error.

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
