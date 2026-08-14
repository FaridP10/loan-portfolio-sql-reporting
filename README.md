# Loan Portfolio SQL Reporting

A simulated loan portfolio, purpose-built to answer the questions a portfolio risk committee actually asks: which segments are riskiest, is credit quality improving or deteriorating over time, and what's the current exposure by segment and region.

## Business Question

Given monthly performance data across a loan book, can we quantify default risk by segment, track whether portfolio quality is improving or deteriorating quarter over quarter, and report current exposure in a form a risk committee could act on?

## Dataset

Simulated, not sourced externally — generated with realistic segment-specific default rates and an intentional "vintage effect" (loans originated later in the window carry more risk, mimicking a softening credit backdrop). Full generation logic is in `generate_data.py` for reference; the SQL project itself only needs the four CSVs in `data/`.

- **2,500 loans** across 5 segments (Prime Mortgage, Prime Personal, Near-Prime Auto, Subprime Personal, Small Business Term) and 5 Canadian regions
- **~38,000 monthly performance snapshots**, Jan 2023 – Dec 2024, each with a delinquency bucket (Current / 30-59 / 60-89 / 90+ / Default) and outstanding balance

## Schema

```
Segment  ──┐
Territory ─┼──< Loans >──< LoanPerformance
           │      (one row per loan            (one row per loan
           │       at origination)               per month)
```

Four tables: `Segment`, `Territory`, `Loans`, `LoanPerformance`. Full DDL in `sql/01_schema.sql`.

## Key Results

**Default rate by segment** (Query 1):

| Segment | Default Rate |
|---|---|
| Subprime Personal Loan | 18.6% |
| Near-Prime Auto | 5.0% |
| Small Business Term Loan | 4.1% |
| Prime Personal Loan | 2.4% |
| Prime Mortgage | 0.6% |

**Quarter-over-quarter delinquency trend** (Query 2) — share of all loan-months each quarter in 90+ days delinquent or default:

| Quarter | 2023 Q1 | Q2 | Q3 | Q4 | 2024 Q1 | Q2 | Q3 | Q4 |
|---|---|---|---|---|---|---|---|---|
| Bad rate | 0.00% | 0.05% | 0.63% | 0.61% | 0.80% | 0.65% | 0.92% | 0.84% |

Delinquency roughly tripled from H1 2023 levels by late 2024 — Query 3 breaks this down by segment and shows it's led by Subprime Personal Loan and Near-Prime Auto, while the Prime segments stay close to flat. That's the kind of finding a portfolio monitoring report exists to surface.

**Current exposure** (Query 4, as of Dec 2024): $270.5M outstanding across 2,366 active loans; 134 loans (5.4%) charged off over the observation window.

## Repo Structure

```
loan-portfolio-sql-reporting/
├── README.md
├── generate_data.py
├── data/
│   ├── segments.csv
│   ├── territory.csv
│   ├── loans.csv
│   └── loan_performance.csv
└── sql/
    ├── 01_schema.sql
    ├── 02_load_data.sql
    └── 03_reporting_queries.sql
```

## How to Run

1. Create a new database (e.g. `LoanPortfolioDB`) in your SQL Server instance.
2. Run `sql/01_schema.sql` against it.
3. Copy the CSVs into the SQL Server container, then run `sql/02_load_data.sql`:
   ```bash
   docker cp data/segments.csv sql1:/tmp/segments.csv
   docker cp data/territory.csv sql1:/tmp/territory.csv
   docker cp data/loans.csv sql1:/tmp/loans.csv
   docker cp data/loan_performance.csv sql1:/tmp/loan_performance.csv
   ```
4. Run the queries in `sql/03_reporting_queries.sql` — each has its expected result noted above it.

## Tech Stack

SQL Server (T-SQL) · Python/pandas for data simulation

## Next Steps

- Add a `Payments` table and compute payment-ratio behavior, mirroring the feature engineering in the companion [Loan Default Risk Model](https://github.com/FaridP10/loan-default-risk-model) project
- Cohort/vintage analysis: default rate by origination quarter, not just calendar quarter
- Power BI or Tableau view on top of Query 3 for a committee-ready visual
