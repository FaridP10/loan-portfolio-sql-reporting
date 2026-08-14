/*
    Loan Portfolio Risk Reporting -- Queries

    Five queries, building from a simple segment breakdown up to the
    quarter-over-quarter trend story. Expected results are noted above each
    query (computed independently in Python during data generation) so you
    can confirm your own run matches.
*/

-- =============================================================================
-- Query 1: Default rate by segment
-- Expected: Subprime Personal Loan ~18.6%, Near-Prime Auto ~5.0%,
--           Small Business ~4.1%, Prime Personal ~2.4%, Prime Mortgage ~0.6%
-- =============================================================================
SELECT
    s.SegmentName,
    s.RiskCategory,
    COUNT(*) AS TotalLoans,
    SUM(CASE WHEN l.LoanStatus = 'Charged Off' THEN 1 ELSE 0 END) AS DefaultedLoans,
    CAST(100.0 * SUM(CASE WHEN l.LoanStatus = 'Charged Off' THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2)) AS DefaultRatePct
FROM dbo.Loans l
JOIN dbo.Segment s ON l.SegmentID = s.SegmentID
GROUP BY s.SegmentName, s.RiskCategory
ORDER BY DefaultRatePct DESC;


-- =============================================================================
-- Query 2: Quarter-over-quarter delinquency trend (90+ Days / Default rate)
-- This is the headline portfolio-monitoring view: what fraction of all
-- loan-months observed each quarter were seriously delinquent or defaulted.
-- Expected: rises from ~0.0% (Q1 2023) toward ~0.9% (Q3 2024), with some
-- quarter-to-quarter noise -- a real deterioration trend, not a straight line.
-- =============================================================================
SELECT
    YEAR(SnapshotDate) AS Yr,
    DATEPART(QUARTER, SnapshotDate) AS Qtr,
    COUNT(*) AS Snapshots,
    CAST(100.0 * SUM(CASE WHEN DelinquencyBucket IN ('90+ Days', 'Default') THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2)) AS BadRatePct
FROM dbo.LoanPerformance
GROUP BY YEAR(SnapshotDate), DATEPART(QUARTER, SnapshotDate)
ORDER BY Yr, Qtr;


-- =============================================================================
-- Query 3: Same trend, broken out by segment
-- Shows WHICH segment is driving the portfolio-wide deterioration seen in
-- Query 2 -- expected to be led by Subprime Personal Loan and, to a lesser
-- extent, Near-Prime Auto, while Prime segments stay closer to flat.
-- =============================================================================
SELECT
    seg.SegmentName,
    YEAR(lp.SnapshotDate) AS Yr,
    DATEPART(QUARTER, lp.SnapshotDate) AS Qtr,
    CAST(100.0 * SUM(CASE WHEN lp.DelinquencyBucket IN ('90+ Days', 'Default') THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2)) AS BadRatePct
FROM dbo.LoanPerformance lp
JOIN dbo.Loans l   ON lp.LoanID = l.LoanID
JOIN dbo.Segment seg ON l.SegmentID = seg.SegmentID
GROUP BY seg.SegmentName, YEAR(lp.SnapshotDate), DATEPART(QUARTER, lp.SnapshotDate)
ORDER BY seg.SegmentName, Yr, Qtr;


-- =============================================================================
-- Query 4: Current outstanding exposure by segment and territory
-- Uses the latest snapshot date only -- a point-in-time exposure view,
-- the kind that would feed a committee's total-exposure slide.
-- =============================================================================
SELECT
    seg.SegmentName,
    t.Region,
    COUNT(DISTINCT lp.LoanID) AS ActiveLoans,
    SUM(lp.OutstandingBalance) AS TotalOutstanding
FROM dbo.LoanPerformance lp
JOIN dbo.Loans l     ON lp.LoanID = l.LoanID
JOIN dbo.Segment seg ON l.SegmentID = seg.SegmentID
JOIN dbo.Territory t ON l.TerritoryID = t.TerritoryID
WHERE lp.SnapshotDate = (SELECT MAX(SnapshotDate) FROM dbo.LoanPerformance)
GROUP BY seg.SegmentName, t.Region
ORDER BY TotalOutstanding DESC;


-- =============================================================================
-- Query 5: Why LEFT JOIN matters here
-- Defaulted-loan count by segment, for Q4 2024 specifically. A prime segment
-- may have ZERO defaults in a given quarter -- an INNER JOIN would silently
-- drop that segment from the report instead of showing 0, which understates
-- how many segments are actually being monitored.
-- =============================================================================
SELECT
    s.SegmentName,
    COUNT(dl.LoanID) AS DefaultsInQ4_2024   -- COUNT on the joined column, not *, so NULLs (no match) count as 0
FROM dbo.Segment s
LEFT JOIN (
    SELECT DISTINCT l.LoanID, l.SegmentID
    FROM dbo.LoanPerformance lp
    JOIN dbo.Loans l ON lp.LoanID = l.LoanID
    WHERE lp.DelinquencyBucket = 'Default'
      AND YEAR(lp.SnapshotDate) = 2024
      AND DATEPART(QUARTER, lp.SnapshotDate) = 4
) dl ON s.SegmentID = dl.SegmentID
GROUP BY s.SegmentName
ORDER BY DefaultsInQ4_2024 DESC;
