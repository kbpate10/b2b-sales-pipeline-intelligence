with enriched as (
    select * from {{ ref('int_deals_enriched') }}
),

-- rep tenure lookup (reuse same proxy logic as rep performance mart)
rep_tenure as (
    select
        sales_agent,
        case
            when (current_date - min(engage_date)) < 365  then '0-1 year'
            when (current_date - min(engage_date)) < 730  then '1-2 years'
            when (current_date - min(engage_date)) < 1095 then '2-3 years'
            else '3+ years'
        end as tenure_bucket
    from enriched
    group by 1
),

base as (
    select
        e.*,
        t.tenure_bucket
    from enriched e
    left join rep_tenure t using (sales_agent)
),

-- cohort by engage month × segment × product series × rep tenure
cohort_metrics as (
    select
        engage_cohort_month,
        account_size_tier,
        product_series,
        sector,
        regional_office,
        tenure_bucket,

        count(*)                                            as total_deals,
        count(case when is_closed then 1 end)               as closed_deals,
        count(case when is_won    then 1 end)               as won_deals,

        round(
            100.0 * count(case when is_won then 1 end)
                  / nullif(count(case when is_closed then 1 end), 0), 1
        )                                                   as win_rate_pct,

        round(avg(case when is_won then close_value end), 2) as avg_deal_size_won,
        round(avg(case when is_won then days_to_close end), 1) as avg_sales_cycle_days,

        round(sum(case when is_won then close_value else 0 end), 2)
                                                            as total_revenue,

        -- pipeline value (open deals)
        round(sum(case when not is_closed then close_value else 0 end), 2)
                                                            as open_pipeline_value,

        -- cohort maturity: % of deals that have closed (tells us if cohort is mature enough to judge)
        round(
            100.0 * count(case when is_closed then 1 end)
                  / nullif(count(*), 0), 1
        )                                                   as cohort_closure_rate_pct

    from base
    where engage_cohort_month is not null
    group by 1, 2, 3, 4, 5, 6
),

-- add rolling 3-month avg win rate using window functions
with_rolling as (
    select
        *,
        round(avg(win_rate_pct) over (
            partition by account_size_tier, product_series
            order by engage_cohort_month
            rows between 2 preceding and current row
        ), 1)                                               as rolling_3m_win_rate_pct
    from cohort_metrics
)

select * from with_rolling
order by engage_cohort_month, account_size_tier, product_series
