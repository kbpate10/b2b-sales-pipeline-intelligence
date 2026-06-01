with transitions as (
    select * from {{ ref('int_stage_transitions') }}
),

-- overall funnel counts
funnel_totals as (
    select
        engage_cohort_month,
        account_size_tier,
        product_series,
        regional_office,

        count(*)                                    as total_deals_entered,
        sum(reached_prospecting)                    as deals_prospecting,
        sum(reached_engaging)                       as deals_engaging,
        sum(reached_won)                            as deals_won,
        sum(reached_terminal - reached_won)         as deals_lost,

        -- conversion rates between stages
        round(
            100.0 * sum(reached_engaging)
                  / nullif(sum(reached_prospecting), 0), 1
        )                                           as prospecting_to_engaging_pct,

        round(
            100.0 * sum(reached_won)
                  / nullif(sum(reached_engaging), 0), 1
        )                                           as engaging_to_won_pct,

        round(
            100.0 * sum(reached_won)
                  / nullif(sum(reached_prospecting), 0), 1
        )                                           as overall_win_rate_pct,

        -- velocity: average days to close for won deals
        round(avg(case when is_won then days_to_close end), 1)
                                                    as avg_days_to_close_won,

        -- revenue
        round(sum(case when is_won then close_value else 0 end), 2)
                                                    as total_revenue_won,

        round(avg(case when is_won then close_value end), 2)
                                                    as avg_deal_size_won,

        -- leak point flag: stage with biggest drop-off
        -- prospecting→engaging loss
        sum(reached_prospecting) - sum(reached_engaging)
                                                    as leak_prospecting_to_engaging,

        -- engaging→won loss
        sum(reached_engaging) - sum(reached_won)    as leak_engaging_to_won

    from transitions
    where engage_cohort_month is not null
    group by 1, 2, 3, 4
),

-- win rate decay by deal age bucket
win_rate_by_age as (
    select
        deal_age_bucket,
        count(*)                                    as closed_deals,
        sum(case when is_won then 1 else 0 end)     as won_deals,
        round(
            100.0 * sum(case when is_won then 1 else 0 end)
                  / nullif(count(*), 0), 1
        )                                           as win_rate_pct
    from transitions
    where is_closed and deal_age_bucket is not null
    group by 1
)

select
    f.*,
    -- annotate which stage leaks more
    case
        when f.leak_prospecting_to_engaging > f.leak_engaging_to_won
        then 'Prospecting → Engaging'
        else 'Engaging → Won'
    end                                             as biggest_leak_stage
from funnel_totals f
