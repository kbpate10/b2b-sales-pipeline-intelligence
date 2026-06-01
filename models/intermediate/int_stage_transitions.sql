-- Computes stage-level metrics per deal and identifies leak points in the funnel.
-- Since the raw data has one row per deal (not one row per stage event),
-- we reconstruct funnel stages by treating each deal as having passed through
-- all stages up to and including its current/final stage.

with enriched as (
    select * from {{ ref('int_deals_enriched') }}
),

-- expand each deal into the stages it passed through
stage_spine as (
    select
        opportunity_id,
        sales_agent,
        account,
        product,
        regional_office,
        account_size_tier,
        product_series,
        engage_date,
        close_date,
        close_value,
        is_won,
        is_closed,
        days_to_close,
        engage_cohort_month,
        stage_order            as final_stage_order,
        deal_stage             as final_stage,

        -- every deal passed through Prospecting (stage 1)
        1                      as reached_prospecting,

        -- deals at stage 2+ passed through Engaging
        case when stage_order >= 2 then 1 else 0 end as reached_engaging,

        -- only closed deals reached terminal stage
        case when is_closed then 1 else 0 end        as reached_terminal,

        -- won specifically
        case when is_won then 1 else 0 end           as reached_won

    from enriched
),

-- win rate decay: how win rate drops as deal age increases
deal_age_buckets as (
    select
        opportunity_id,
        is_won,
        case
            when days_to_close <= 30  then '0-30 days'
            when days_to_close <= 60  then '31-60 days'
            when days_to_close <= 90  then '61-90 days'
            when days_to_close <= 180 then '91-180 days'
            else                           '180+ days'
        end as deal_age_bucket,
        days_to_close
    from stage_spine
    where is_closed
)

select
    s.*,
    d.deal_age_bucket
from stage_spine s
left join deal_age_buckets d using (opportunity_id)
