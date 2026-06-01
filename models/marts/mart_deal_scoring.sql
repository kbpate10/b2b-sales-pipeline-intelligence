-- Deal scoring model: assigns each open deal a score from 0-100
-- and buckets it into Hot / Warm / Cold.
-- Scoring dimensions: stage progression, recency, account quality, historical win rate.

with enriched as (
    select * from {{ ref('int_deals_enriched') }}
    where not is_closed  -- score only open deals
),

-- historical win rates by product series and account size tier
-- used as a signal for how likely this deal type is to close
historical_win_rates as (
    select
        product_series,
        account_size_tier,
        count(*)                                        as total_closed,
        sum(case when is_won then 1 else 0 end)         as total_won,
        round(
            100.0 * sum(case when is_won then 1 else 0 end)
                  / nullif(count(*), 0), 1
        )                                               as segment_win_rate_pct
    from {{ ref('int_deals_enriched') }}
    where is_closed
    group by 1, 2
),

scored as (
    select
        e.opportunity_id,
        e.sales_agent,
        e.manager,
        e.regional_office,
        e.account,
        e.product,
        e.product_series,
        e.deal_stage,
        e.engage_date,
        e.account_size_tier,
        e.revenue_tier,
        e.account_revenue,
        e.open_deal_age_days,
        e.is_stalled,
        coalesce(h.segment_win_rate_pct, 0) as segment_win_rate_pct,

        -- SCORE COMPONENTS (each out of 100, then weighted)

        -- 1. Stage score: further along = higher score
        case e.deal_stage
            when 'Engaging'     then 70
            when 'Prospecting'  then 30
            else 0
        end                                             as stage_score,

        -- 2. Recency score: penalizes deals that have been stagnant
        -- fresh deal (<14 days) = 100, stale (>60 days) = 0
        case
            when e.open_deal_age_days <= 14  then 100
            when e.open_deal_age_days <= 30  then 75
            when e.open_deal_age_days <= 60  then 40
            when e.open_deal_age_days <= 90  then 15
            else 0
        end                                             as recency_score,

        -- 3. Account quality score: based on account revenue tier
        case e.revenue_tier
            when 'Large'    then 100
            when 'Medium'   then 60
            when 'Small'    then 30
            else 0
        end                                             as account_quality_score,

        -- 4. Historical win rate score for this product+segment combo
        -- normalize 0-100% win rate to 0-100 score
        round(coalesce(h.segment_win_rate_pct, 0), 0)  as historical_win_rate_score

    from enriched e
    left join historical_win_rates h
           on e.product_series   = h.product_series
          and e.account_size_tier = h.account_size_tier
),

weighted as (
    select
        *,
        -- weighted composite score
        -- stage: 35%, recency: 30%, account quality: 20%, historical win rate: 15%
        round(
            (stage_score              * 0.35)
          + (recency_score            * 0.30)
          + (account_quality_score    * 0.20)
          + (historical_win_rate_score * 0.15)
        , 1)                                            as deal_score
    from scored
)

select
    *,
    case
        when deal_score >= 70 then 'Hot'
        when deal_score >= 45 then 'Warm'
        else                       'Cold'
    end                                                 as deal_tier
from weighted
order by deal_score desc
