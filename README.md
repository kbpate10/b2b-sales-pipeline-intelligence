# B2B Sales Pipeline Intelligence Engine

**Stack:** SQL | dbt | DuckDB | Tableau Public

---

## Problem Statement

Most sales analytics projects stop at basic reporting: total revenue, deals closed, quota attainment. These numbers tell you what happened, not why it happened or where the business is leaking money.

B2B sales teams lose deals at predictable points in the pipeline, carry stale opportunities that will never close, and misattribute rep performance to individual skill when territory quality is the real driver. Without granular funnel analysis, ops teams make coaching decisions and headcount calls based on incomplete information.

This project builds a full pipeline intelligence layer on top of raw CRM data, covering funnel conversion, rep performance normalization, deal scoring, and cohort analysis, using production-grade tooling that mirrors how modern data teams operate.

---

## Why This Project

Revenue operations is one of the highest-leverage functions at a B2B company. Decisions made here directly affect how sales teams are structured, which deals get attention, and how forecasts are built. Analytics work in this space requires understanding the business logic deeply, not just writing queries.

The specific analyses in this project, particularly territory-normalized rep performance and deal scoring, are the types of work that distinguish data teams that drive decisions from those that produce dashboards nobody acts on.

The dataset used is a real CRM export from Maven Analytics covering 8,800 opportunity records across accounts, products, and sales teams. No synthetic data was generated.

---

## Dataset

**Source:** [Maven Analytics CRM Sales Opportunities](https://mavenanalytics.io/data-playground/crm-sales-opportunities)

| Table | Rows | Description |
|---|---|---|
| `sales_pipeline.csv` | 8,800 | Core opportunity records with stage, dates, and close value |
| `accounts.csv` | 85 | Company accounts with sector, revenue, employee count |
| `sales_teams.csv` | 35 | Sales reps with manager and regional office |
| `products.csv` | 7 | Product catalog with series and list pricing |

---

## Architecture

```
Raw CSV Files (Maven Analytics)
        |
        v
   dbt seed (DuckDB)
        |
        v
  Staging Layer       -- type casting, cleaning, derived flags
        |
        v
  Intermediate Layer  -- dimension joins, funnel stage expansion
        |
        v
  Mart Layer          -- business-ready analytical tables
        |
        v
  Tableau Public      -- interactive dashboard (in progress)
```

The project uses **dbt Core** for transformation with **DuckDB** as the local analytical engine. The architecture mirrors production stacks at modern SaaS companies, with the only difference being the warehouse layer, which can be swapped to Snowflake or BigQuery by changing a single config file.

---

## dbt Project Structure

```
models/
├── staging/
│   ├── stg_opportunities.sql     # cleaned deals with derived flags
│   ├── stg_accounts.sql          # account size and revenue tiers
│   ├── stg_sales_teams.sql       # rep and manager hierarchy
│   └── stg_products.sql          # product catalog
├── intermediate/
│   ├── int_deals_enriched.sql    # all dimensions joined onto opportunities
│   └── int_stage_transitions.sql # funnel stage flags and deal age buckets
└── marts/
    ├── mart_funnel_analysis.sql   # conversion rates, velocity, leak points
    ├── mart_rep_performance.sql   # raw and territory-normalized rankings
    ├── mart_deal_scoring.sql      # open deal scoring (Hot / Warm / Cold)
    └── mart_cohort_analysis.sql   # win rate by cohort, segment, tenure
```

Every mart model is materialized as a table. Staging and intermediate models are views. All models have documented columns, data tests, and are connected in a full DAG visible via `dbt docs serve`.

---

## Analytical Models

### 1. Funnel Analysis (`mart_funnel_analysis`)

Tracks how many deals enter each pipeline stage and what percentage advance to the next. Aggregated by cohort month, account size tier, product series, and regional office.

Key metrics produced:
- `prospecting_to_engaging_pct` -- share of deals that move from initial contact to active negotiation
- `engaging_to_won_pct` -- close rate on deals that reached active stage
- `overall_win_rate_pct` -- end-to-end conversion from pipeline entry to closed won
- `avg_days_to_close_won` -- average sales cycle for won deals
- `biggest_leak_stage` -- which stage loses the most deals in absolute terms

This model answers the question every sales leader actually cares about: where is pipeline dying, and how fast are deals moving through each stage.

---

### 2. Rep Performance with Territory Normalization (`mart_rep_performance`)

This is the analysis that most sales analytics projects skip.

Raw revenue rank is misleading. A rep covering enterprise accounts in a high-revenue region will outperform an equally skilled rep working SMB accounts in a weaker territory, purely due to account mix. Ranking reps on revenue alone rewards geography, not skill.

This model computes a `territory_quality_index` for each rep using SQL window functions:

```sql
avg_territory_account_revenue
/ avg(avg_territory_account_revenue) over (partition by regional_office)
```

This produces a ratio representing how rich a rep's account base is compared to their regional peers. Revenue is then adjusted using this index to produce `territory_adjusted_revenue`, which is the basis for `global_rank_normalized`.

The result: two reps with identical raw revenue numbers may have very different normalized ranks if one worked harder accounts to get there. This is the number a VP of Sales should use for performance reviews, not raw attainment.

Additional metrics:
- `rank_in_region` and `global_rank_raw` -- for comparison against normalized rank
- `avg_days_to_close` -- sales velocity per rep
- `win_rate_pct` -- close rate on worked deals
- `tenure_bucket` -- rep experience bracket approximated from first deal date

---

### 3. Deal Scoring (`mart_deal_scoring`)

Every open deal is scored from 0 to 100 and bucketed into Hot, Warm, or Cold. The score is a weighted composite of four signals:

| Signal | Weight | Logic |
|---|---|---|
| Stage progression | 35% | Engaging = 70pts, Prospecting = 30pts |
| Recency | 30% | Deals open under 14 days score 100, over 90 days score near 0 |
| Account quality | 20% | Based on account revenue tier (Large / Medium / Small) |
| Historical win rate | 15% | Win rate for this product series and account size combination |

Tier cutoffs: Hot >= 70, Warm >= 45, Cold < 45.

This gives sales managers a prioritized view of where to focus rep time, and flags stale deals that should be either accelerated or written off.

---

### 4. Cohort Analysis (`mart_cohort_analysis`)

Groups deals by the month they entered the pipeline, then slices by account size tier, product series, industry sector, regional office, and rep tenure bracket.

Key metrics per cohort:
- `win_rate_pct` -- conversion rate for this cohort and segment combination
- `avg_deal_size_won` -- average close value for won deals
- `avg_sales_cycle_days` -- how long deals took to close
- `cohort_closure_rate_pct` -- share of deals in this cohort that have closed (used to assess cohort maturity before drawing conclusions)
- `rolling_3m_win_rate_pct` -- 3-month rolling average using a window function to smooth out noise in monthly figures

This model answers questions like: are deals sourced from enterprise accounts in Q1 closing at a higher rate than mid-market deals from Q3? Are newer reps improving over time? Which product series has the fastest sales cycle?

---

## Data Quality

dbt tests are defined for all layers. 25 tests run on every model execution.

Tests include:
- `not_null` on all primary keys and non-nullable business fields
- `unique` on grain columns (opportunity_id, sales_agent, product)
- `accepted_values` on categorical fields (deal_stage, account_size_tier, deal_tier)
- `assert_no_negative_deal_value` -- custom singular test that fails if any closed-won deal has a zero or negative close value

All 25 tests pass on the current dataset.

---

## How to Run

### Requirements

- Python 3.8+
- dbt-duckdb

```bash
pip install dbt-duckdb
```

### Steps

1. Clone the repo
2. Download the 4 CSV files from [Maven Analytics](https://mavenanalytics.io/data-playground/crm-sales-opportunities) and place them in `seeds/`
3. From the project root:

```bash
dbt seed --profiles-dir .        # load CSVs into DuckDB
dbt run --profiles-dir .         # build all models
dbt test --profiles-dir .        # run data quality tests
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .  # view DAG at localhost:8080
```

---

## Results

- 10 dbt models built across 3 layers (staging, intermediate, marts)
- 25 data quality tests, all passing
- 8,800 opportunity records processed across 4 dimension tables
- 4 analytical mart tables ready for dashboard consumption:
  - Funnel conversion rates by cohort, segment, and region
  - Territory-adjusted rep rankings separating skill from territory luck
  - Scored and tiered open pipeline for prioritization
  - Cohort win rates with rolling 3-month smoothing
