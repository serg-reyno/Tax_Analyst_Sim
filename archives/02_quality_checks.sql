-- QUALITY CHECKS --

-- ====================================================================================================== 
-- ACCOUNTS TABLE QUALITY CHECKS 
-- ======================================================================================================  


-- Scale: Count total accounts
-- Expected result: Record count should match the expected number of accounts loaded into the dataset
SELECT COUNT(*)  
FROM accounts; 


-- Uniqueness: Check for duplicate account IDs
-- Expected result: 0 records
SELECT 
    account_id, 
    COUNT(*) AS duplicate_count 
FROM accounts 
GROUP BY account_id 
HAVING COUNT(*) > 1; 


-- Completeness: Check for missing required fields
-- Expected result: 0 records
SELECT * 
FROM accounts 
WHERE account_id IS NULL 
   OR account_type IS NULL; 


-- Validity: Review account types
-- Expected result: Only approved account types used within the dataset should appear
-- Unexpected categories or inconsistent formatting should be investigated
SELECT 
    account_type, 
    COUNT(*) AS account_count 
FROM accounts 
GROUP BY account_type; 


-- Validity: Review account opening dates
-- Expected result: 0 records
-- Accounts should not have opening dates in the future
SELECT * 
FROM accounts 
WHERE opening_date > CURRENT_DATE;

-- ======================================================================================================
-- COST BASIS QUALITY CHECKS
-- ======================================================================================================

-- Scale: Count total cost basis records
-- Expected result: Record count should match the expected number of cost basis records loaded into the dataset
SELECT COUNT(*) AS cost_basis_count
FROM cost_basis;


-- Uniqueness: Check for duplicate transaction IDs
-- Expected result: 0 records
SELECT
    transaction_id,
    COUNT(*) AS duplicate_count
FROM cost_basis
GROUP BY transaction_id
HAVING COUNT(*) > 1;


-- Completeness: Check for missing required fields
-- Expected result: 0 records
SELECT *
FROM cost_basis
WHERE transaction_id IS NULL
   OR cost_basis IS NULL
   OR realized_gain_loss IS NULL;


-- Validity: Review range of cost basis and realized gain/loss values
-- Expected result: Cost basis values should generally be zero or positive;
-- realized gain/loss may be positive, negative, or zero. Extreme values should be investigated.
SELECT
    MIN(cost_basis) AS minimum_cost_basis,
    MAX(cost_basis) AS maximum_cost_basis,
    AVG(cost_basis) AS average_cost_basis,
    MIN(realized_gain_loss) AS minimum_gain_loss,
    MAX(realized_gain_loss) AS maximum_gain_loss,
    AVG(realized_gain_loss) AS average_gain_loss
FROM cost_basis;


-- Validity: Check for zero cost basis amounts
-- Expected result: Ideally 0 records; any zero-basis records should be reviewed to determine whether they are legitimate
SELECT *
FROM cost_basis
WHERE cost_basis = 0;


-- Validity: Check for negative cost basis amounts
-- Expected result: 0 records
SELECT *
FROM cost_basis
WHERE cost_basis < 0;

-- Uniqueness: Check for duplicate basis record IDs
-- Expected result: 0 records
SELECT
    basis_record_id,
    COUNT(*) AS duplicate_count
FROM cost_basis
GROUP BY basis_record_id
HAVING COUNT(*) > 1;

-- ====================================================================================================== 
-- TAX FORMS QUALITY CHECKS 
-- ====================================================================================================== 

-- Scale: Count total tax form records
-- Expected result: Record count should match the expected number of tax forms loaded into the dataset
SELECT COUNT(*) AS tax_forms_count 
FROM tax_forms; 
 

-- Uniqueness: Check for duplicate tax form IDs
-- Expected result: 0 records
SELECT 
    tax_form_id, 
    COUNT(*) AS duplicate_count 
FROM tax_forms 
GROUP BY tax_form_id 
HAVING COUNT(*) > 1; 
 

-- Completeness: Check for missing required fields
-- Expected result: 0 records
SELECT * 
FROM tax_forms 
WHERE tax_form_id IS NULL 
   OR account_id IS NULL 
   OR form_type IS NULL 
   OR tax_year IS NULL 
   OR status IS NULL; 
 

-- Validity: Review tax years in the dataset
-- Expected result: Earliest and latest tax years should fall within the intended dataset period
SELECT 
    MIN(tax_year) AS earliest_tax_year, 
    MAX(tax_year) AS latest_tax_year 
FROM tax_forms; 
 

-- Validity: Review form types
-- Expected result: Only valid and consistently formatted tax form types should appear
SELECT 
    form_type, 
    COUNT(*) AS form_count 
FROM tax_forms 
GROUP BY form_type 
ORDER BY form_count DESC; 
 

-- Validity: Review status values
-- Expected result: Only valid and consistently formatted status values should appear
SELECT 
    status, 
    COUNT(*) AS status_count 
FROM tax_forms 
GROUP BY status 
ORDER BY status_count DESC; 
 

-- Validity: Identify negative reported proceeds
-- Expected result: 0 records
SELECT * 
FROM tax_forms 
WHERE reported_proceeds < 0; 
 

-- Validity: Identify negative reported cost basis
-- Expected result: 0 records
SELECT * 
FROM tax_forms 
WHERE reported_cost_basis < 0; 
 

-- Validity: Check for negative dividend amounts
-- Expected result: 0 records
SELECT * 
FROM tax_forms 
WHERE reported_dividends < 0; 
 

-- Validity: Check for negative interest amounts
-- Expected result: 0 records
SELECT * 
FROM tax_forms 
WHERE reported_interest < 0; 
 

-- Validity: Check for negative federal withholding
-- Expected result: 0 records
SELECT * 
FROM tax_forms 
WHERE federal_tax_withheld < 0; 
 

-- Reasonableness: Review reported value ranges
-- Expected result: Values should fall within plausible ranges for the simulated dataset;
-- negative realized gain/loss values may be valid, while extreme outliers should be investigated
SELECT 
    MIN(reported_proceeds) AS min_proceeds, 
    MAX(reported_proceeds) AS max_proceeds, 
    AVG(reported_proceeds) AS avg_proceeds, 
 
    MIN(reported_cost_basis) AS min_cost_basis, 
    MAX(reported_cost_basis) AS max_cost_basis, 
    AVG(reported_cost_basis) AS avg_cost_basis, 
 
    MIN(reported_gain_loss) AS min_gain_loss, 
    MAX(reported_gain_loss) AS max_gain_loss, 
    AVG(reported_gain_loss) AS avg_gain_loss, 
 
    MIN(reported_dividends) AS min_dividends, 
    MAX(reported_dividends) AS max_dividends, 
 
    MIN(reported_interest) AS min_interest, 
    MAX(reported_interest) AS max_interest, 
 
    MIN(federal_tax_withheld) AS min_tax_withheld, 
    MAX(federal_tax_withheld) AS max_tax_withheld 
FROM tax_forms;
-- ======================================================================================================
-- TRANSACTIONS QUALITY CHECKS
-- ======================================================================================================

-- Row Count
-- Expected result: Positive transaction volume greater than 0.
-- The number of records should align with the expected reporting period and business activity.
SELECT COUNT(*) 
AS transactions_count 
FROM transactions;


-- Duplicate Transactions
-- Expected result: 0 records.
-- Each transaction_id should represent one unique business transaction.
-- Duplicate transaction IDs could cause inaccurate tax reporting, duplicate gains/losses, or incorrect reconciliations.
SELECT
    transaction_id,
    COUNT(*) AS duplicate_count
FROM transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1;


-- Missing Critical Values 
-- Expected result: 0 records.
-- Required fields (account_id, security_symbol, transaction_type, and trade_date)
-- should be populated to support transaction classification, reporting, and downstream tax calculations.
SELECT
    COUNT(*) AS missing_critical_fields
FROM transactions
WHERE account_id IS NULL
   OR security_symbol IS NULL
   OR transaction_type IS NULL
   OR trade_date IS NULL;


-- Transaction Types
-- Expected result: Only valid transaction categories should appear.
-- Expected values may include BUY, SELL, DIVIDEND, INTEREST, TRANSFER, or other approved transaction types.
-- Transaction volumes should be reasonable and consistent with expected business activity.
SELECT
    transaction_type,
    COUNT(*) AS transaction_count
FROM transactions
GROUP BY transaction_type
ORDER BY transaction_count DESC;


-- Orphan Transactions
-- Expected result: 0 records.
-- Every transaction should link to an existing account in the accounts table.
-- Missing account relationships indicate broken data integrity and could impact customer tax reporting.
SELECT
    t.account_id,
    COUNT(*) AS transaction_count
FROM transactions t
LEFT JOIN accounts a
    ON t.account_id = a.account_id
WHERE a.account_id IS NULL
GROUP BY t.account_id;


-- Date Range for Transactions
-- Expected result: Dates should fall within the expected reporting period.
-- Earliest and latest trade dates should match the timeframe being analyzed.
-- Future-dated transactions should not exist unless they represent scheduled activity.
SELECT
    MIN(trade_date) AS earliest_trade,
    MAX(trade_date) AS latest_trade
FROM transactions;


-- Strange Dollar Amounts
-- Expected result: 0 records.
-- Gross amounts should contain valid transaction values.
-- NULL or zero-dollar transactions should be reviewed because they may indicate incomplete records or processing errors.
SELECT
    transaction_id,
    transaction_type,
    gross_amount
FROM transactions
WHERE gross_amount IS NULL
   OR gross_amount = 0;


-- View Transaction Amount Range
-- Expected result: Transaction amounts should fall within reasonable ranges based on transaction type.
-- BUY and SELL transactions should generally contain positive dollar amounts.
-- Extreme outliers should be investigated for data entry errors or unusual activity.
SELECT
    transaction_type,
    COUNT(*) AS count_transactions,
    MIN(gross_amount) AS minimum_amount,
    MAX(gross_amount) AS maximum_amount
FROM transactions
GROUP BY transaction_type;

-- ======================================================================================================
-- WITHHOLDINGS QUALITY CHECKS
-- ======================================================================================================

-- Scale: Count total withholding records
-- Expected result: Record count should match the expected number of withholding records loaded into the dataset
SELECT COUNT(*) 
AS withholding_count 
FROM withholding;


-- Validity: Check for duplicate withholding transaction IDs
-- Expected result: 0 records
-- Each transaction should have at most one withholding record in this dataset
SELECT
    transaction_id,
    COUNT(*) AS duplicate_count
FROM withholding
GROUP BY transaction_id
HAVING COUNT(*) > 1;


-- Completeness: Check for missing required fields
-- Expected result: 0 records
-- Each withholding record should contain a transaction ID, withholding type, and withholding amount
SELECT *
FROM withholding
WHERE transaction_id IS NULL
   OR withholding_type IS NULL
   OR withholding_amount IS NULL;


-- Validity: Review withholding types
-- Expected result: Only valid and consistently formatted withholding types should appear
-- Unexpected categories or inconsistent formatting should be investigated
SELECT
    withholding_type,
    COUNT(*) AS withholding_type_count
FROM withholding
GROUP BY withholding_type
ORDER BY withholding_type_count DESC;


-- Validity: Check for negative withholding amounts
-- Expected result: 0 records
-- Withholding amounts should not be negative
SELECT *
FROM withholding
WHERE withholding_amount < 0;


-- Validity: Review withholding amount ranges
-- Expected result: Withholding amounts should generally be zero or positive;
-- unusually large amounts should be investigated as potential data-quality exceptions
SELECT
    MIN(withholding_amount) AS minimum_withholding,
    MAX(withholding_amount) AS maximum_withholding,
    AVG(withholding_amount) AS average_withholding
FROM withholding;













   









   