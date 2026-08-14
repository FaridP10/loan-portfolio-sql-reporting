"""
Generate a simulated loan portfolio dataset for SQL portfolio-risk reporting.

Design intent: multiple risk segments with different baseline default rates,
a "vintage effect" (loans originated later carry more risk, simulating looser
underwriting / a softening macro backdrop), and monthly performance snapshots
that ramp through delinquency buckets before charge-off. This produces a
believable, checkable quarter-over-quarter deterioration story for the
reporting queries to surface.
"""
import numpy as np
import pandas as pd
from datetime import date
from dateutil.relativedelta import relativedelta

rng = np.random.default_rng(42)

OBS_CUTOFF = date(2024, 12, 31)
ORIGINATION_START = date(2023, 1, 1)
ORIGINATION_END = date(2024, 6, 30)
N_LOANS = 2500

# ---------------------------------------------------------------------------
# Dimension: Segments
# ---------------------------------------------------------------------------
segments = pd.DataFrame([
    # segment_id, name,                     risk_category, weight, default_prob, avg_months_to_default, amt_lo, amt_hi, term, rate_lo, rate_hi
    (1, "Prime Mortgage",           "Prime",      0.20, 0.025, 30, 250000, 650000, 360, 4.5, 6.0),
    (2, "Prime Personal Loan",      "Prime",      0.20, 0.05,  14,   5000,  25000,  48, 7.0, 10.0),
    (3, "Near-Prime Auto",          "Near-Prime", 0.25, 0.09,  16,  15000,  40000,  60, 9.0, 13.0),
    (4, "Subprime Personal Loan",   "Subprime",   0.15, 0.22,  10,   3000,  15000,  36, 15.0, 22.0),
    (5, "Small Business Term Loan", "Near-Prime", 0.20, 0.13,  18,  20000, 150000,  84, 8.0, 12.0),
], columns=["SegmentID", "SegmentName", "RiskCategory", "weight", "default_prob",
            "avg_months_to_default", "amt_lo", "amt_hi", "term", "rate_lo", "rate_hi"])

# ---------------------------------------------------------------------------
# Dimension: Territory
# ---------------------------------------------------------------------------
territory = pd.DataFrame([
    (1, "Ontario", "Canada", 0.38),
    (2, "Quebec", "Canada", 0.22),
    (3, "British Columbia", "Canada", 0.18),
    (4, "Alberta", "Canada", 0.14),
    (5, "Atlantic Canada", "Canada", 0.08),
], columns=["TerritoryID", "Region", "Country", "weight"])

# ---------------------------------------------------------------------------
# Loans
# ---------------------------------------------------------------------------
def random_dates(n, start, end):
    days = (end - start).days
    offsets = rng.integers(0, days + 1, size=n)
    return [start + pd.Timedelta(days=int(d)) for d in offsets]

origination_dates = random_dates(N_LOANS, ORIGINATION_START, ORIGINATION_END)
origination_dates = pd.to_datetime(origination_dates)

# Vintage risk multiplier: rises smoothly across the 6 origination quarters (Q1'23-Q2'24)
def quarter_index(d):
    return (d.year - 2023) * 4 + (d.quarter - 1)

vintage_multiplier = 0.85 + (pd.Series(origination_dates).apply(quarter_index) / 5) * 0.5

segment_choice = rng.choice(segments["SegmentID"], size=N_LOANS, p=segments["weight"])
territory_choice = rng.choice(territory["TerritoryID"], size=N_LOANS, p=territory["weight"])

loans = pd.DataFrame({
    "LoanID": np.arange(1, N_LOANS + 1),
    "SegmentID": segment_choice,
    "TerritoryID": territory_choice,
    "OriginationDate": origination_dates,
})
loans = loans.merge(segments, on="SegmentID", how="left")
loans["vintage_multiplier"] = vintage_multiplier.values

loans["LoanAmount"] = rng.uniform(loans["amt_lo"], loans["amt_hi"]).round(-2)
loans["TermMonths"] = loans["term"]
loans["InterestRate"] = rng.uniform(loans["rate_lo"], loans["rate_hi"]).round(2)

final_default_prob = (loans["default_prob"] * loans["vintage_multiplier"]).clip(upper=0.65)
loans["will_default"] = rng.random(N_LOANS) < final_default_prob

months_to_default = rng.gamma(
    shape=4.0,
    scale=(loans["avg_months_to_default"] / 4.0).clip(lower=1),
).round().astype(int).clip(min=3)
loans["months_to_default"] = np.where(loans["will_default"], months_to_default, np.nan)

default_date = loans["OriginationDate"] + pd.to_timedelta(
    (loans["months_to_default"].fillna(0) * 30.44), unit="D"
)
loans["default_date"] = np.where(loans["will_default"], default_date, pd.NaT)
loans["default_date"] = pd.to_datetime(loans["default_date"])

# Only counts as an in-window default if it lands before the observation cutoff
loans["defaults_in_window"] = loans["will_default"] & (loans["default_date"].dt.date <= OBS_CUTOFF)
loans["LoanStatus"] = np.where(loans["defaults_in_window"], "Charged Off", "Active")

loans_out = loans[[
    "LoanID", "SegmentID", "TerritoryID", "OriginationDate", "LoanAmount",
    "TermMonths", "InterestRate", "LoanStatus"
]].copy()
loans_out["OriginationDate"] = loans_out["OriginationDate"].dt.strftime("%Y-%m-%d")

# ---------------------------------------------------------------------------
# Monthly performance snapshots
# ---------------------------------------------------------------------------
BUCKET_RAMP = ["30-59 Days", "60-89 Days", "90+ Days", "Default"]

perf_rows = []
early_delinq_p_by_risk = {"Prime": 0.015, "Near-Prime": 0.03, "Subprime": 0.06}

for row in loans.itertuples():
    start = row.OriginationDate.date()
    end_month = row.default_date.date() if (row.defaults_in_window and pd.notna(row.default_date)) else OBS_CUTOFF
    end_month = min(end_month, OBS_CUTOFF)

    cur = date(start.year, start.month, 1)
    months = []
    while cur <= end_month:
        months.append(cur)
        cur = (cur + relativedelta(months=1))
    if not months:
        continue

    n = len(months)
    ramp_len = len(BUCKET_RAMP) if row.defaults_in_window else 0
    steady_len = max(n - ramp_len, 0)

    p_blip = early_delinq_p_by_risk[row.RiskCategory]
    buckets = []
    for i in range(steady_len):
        buckets.append("30-59 Days" if rng.random() < p_blip else "Current")
    if row.defaults_in_window:
        buckets.extend(BUCKET_RAMP[-min(ramp_len, n):])
    buckets = buckets[:n]

    for i, m in enumerate(months):
        months_elapsed = i + 1
        pct_elapsed = min(months_elapsed / row.TermMonths, 1.0)
        outstanding = round(row.LoanAmount * (1 - pct_elapsed), 2)
        snapshot_date = date(m.year, m.month, 1) + relativedelta(day=31)  # month-end
        perf_rows.append((row.LoanID, snapshot_date.strftime("%Y-%m-%d"), buckets[i], outstanding))

loan_performance = pd.DataFrame(perf_rows, columns=["LoanID", "SnapshotDate", "DelinquencyBucket", "OutstandingBalance"])

# ---------------------------------------------------------------------------
# Write CSVs
# ---------------------------------------------------------------------------
segments[["SegmentID", "SegmentName", "RiskCategory"]].to_csv("data/segments.csv", index=False)
territory[["TerritoryID", "Region", "Country"]].to_csv("data/territory.csv", index=False)
loans_out.to_csv("data/loans.csv", index=False)
loan_performance.to_csv("data/loan_performance.csv", index=False)

print("Loans:", loans_out.shape)
print("Performance rows:", loan_performance.shape)
print()
print("Default rate by segment (in-window):")
print(loans.groupby("SegmentName")["defaults_in_window"].mean().round(3))
