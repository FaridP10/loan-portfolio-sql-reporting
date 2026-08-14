/*
    Loan Portfolio Risk Reporting -- Schema
    Run this first, against your target database (e.g. LoanPortfolioDB).
*/

CREATE TABLE dbo.Segment (
    SegmentID     INT           NOT NULL PRIMARY KEY,
    SegmentName   VARCHAR(50)   NOT NULL,
    RiskCategory  VARCHAR(20)   NOT NULL   -- Prime / Near-Prime / Subprime
);

CREATE TABLE dbo.Territory (
    TerritoryID   INT           NOT NULL PRIMARY KEY,
    Region        VARCHAR(50)   NOT NULL,
    Country       VARCHAR(50)   NOT NULL
);

CREATE TABLE dbo.Loans (
    LoanID        INT           NOT NULL PRIMARY KEY,
    SegmentID     INT           NOT NULL,
    TerritoryID   INT           NOT NULL,
    OriginationDate DATE        NOT NULL,
    LoanAmount    DECIMAL(12,2) NOT NULL,
    TermMonths    INT           NOT NULL,
    InterestRate  DECIMAL(5,2)  NOT NULL,
    LoanStatus    VARCHAR(20)   NOT NULL,   -- Active / Charged Off
    CONSTRAINT FK_Loans_Segment   FOREIGN KEY (SegmentID)   REFERENCES dbo.Segment(SegmentID),
    CONSTRAINT FK_Loans_Territory FOREIGN KEY (TerritoryID) REFERENCES dbo.Territory(TerritoryID)
);

-- One row per loan per month: this is what makes quarter-over-quarter
-- trending possible -- each loan's delinquency status is tracked over time,
-- not just as a single current snapshot.
CREATE TABLE dbo.LoanPerformance (
    LoanID             INT           NOT NULL,
    SnapshotDate       DATE          NOT NULL,
    DelinquencyBucket  VARCHAR(20)   NOT NULL,  -- Current / 30-59 Days / 60-89 Days / 90+ Days / Default
    OutstandingBalance DECIMAL(12,2) NOT NULL,
    CONSTRAINT PK_LoanPerformance PRIMARY KEY (LoanID, SnapshotDate),
    CONSTRAINT FK_LoanPerformance_Loans FOREIGN KEY (LoanID) REFERENCES dbo.Loans(LoanID)
);
