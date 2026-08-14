/*
    Loan Portfolio Risk Reporting -- Data Load
    Prerequisite: CSVs copied into the SQL Server container (see README).
    Load order matters: Segment/Territory before Loans (FK dependency),
    then LoanPerformance last.
*/

BULK INSERT dbo.Segment
FROM '/tmp/segments.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Territory
FROM '/tmp/territory.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Loans
FROM '/tmp/loans.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.LoanPerformance
FROM '/tmp/loan_performance.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-- Sanity check row counts after loading
SELECT 'Segment' AS TableName, COUNT(*) AS RecordCount FROM dbo.Segment
UNION ALL SELECT 'Territory', COUNT(*) FROM dbo.Territory
UNION ALL SELECT 'Loans', COUNT(*) FROM dbo.Loans
UNION ALL SELECT 'LoanPerformance', COUNT(*) FROM dbo.LoanPerformance;
GO

-- Expected: Segment=5, Territory=5, Loans=2500, LoanPerformance=37947
