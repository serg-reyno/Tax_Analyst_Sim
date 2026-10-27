-- DEFINE SCHEMA  --

-- Create Tables before loading Data from CSV files -- 
CREATE TABLE accounts (
    account_id VARCHAR(20) PRIMARY KEY,
    customer_name VARCHAR(100),
    account_type VARCHAR(30),
    tax_residency VARCHAR(20),
    tax_document_type VARCHAR(20),
    w9_status VARCHAR(30),
    w8_status VARCHAR(30),
    backup_withholding_flag BOOLEAN,
    nra_withholding_flag BOOLEAN,
    opening_date DATE,
    account_status VARCHAR(20)
);

CREATE TABLE transactions (
    transaction_id VARCHAR(20) PRIMARY KEY,
    account_id VARCHAR(20),
    security_symbol VARCHAR(20),
    security_type VARCHAR(30),
    transaction_type VARCHAR(30),
    trade_date DATE,
    settlement_date DATE,
    quantity NUMERIC,
    price NUMERIC,
    gross_amount NUMERIC,
    currency VARCHAR(10),
    description TEXT
);

CREATE TABLE cost_basis (
    basis_record_id VARCHAR(20) PRIMARY KEY,
    transaction_id VARCHAR(20),
    account_id VARCHAR(20),
    security_symbol VARCHAR(20),
    security_type VARCHAR(30),
    acquisition_date DATE,
    sale_date DATE,
    quantity_sold NUMERIC,
    cost_basis NUMERIC,
    proceeds NUMERIC,
    realized_gain_loss NUMERIC,
    wash_sale_adjustment NUMERIC,
    adjusted_gain_loss NUMERIC,
    covered_status VARCHAR(20),
    holding_period VARCHAR(20)
);

CREATE TABLE tax_forms (
    tax_form_id VARCHAR(20) PRIMARY KEY,
    account_id VARCHAR(20),
    form_type VARCHAR(20),
    tax_year INTEGER,
    reported_proceeds NUMERIC,
    reported_cost_basis NUMERIC,
    reported_gain_loss NUMERIC,
    reported_dividends NUMERIC,
    reported_interest NUMERIC,
    federal_tax_withheld NUMERIC,
    status VARCHAR(20)
);

CREATE TABLE withholding (
    withholding_id VARCHAR(20) PRIMARY KEY,
    account_id VARCHAR(20),
    transaction_id VARCHAR(20),
    withholding_type VARCHAR(30),
    income_type VARCHAR(30),
    gross_payment NUMERIC,
    withholding_rate NUMERIC,
    withholding_amount NUMERIC,
    withholding_date DATE,
    documentation_status VARCHAR(30)
);


-- Pull up sample data to confirm data is formatted correclty  --
SELECT *
FROM accounts
LIMIT 10;