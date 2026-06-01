-- Rep performance with territory normalization.
-- The key insight: a rep in a high-revenue territory will look better on raw numbers
-- than an equally skilled rep in a weak territory. Window functions let us
-- adjust for territory quality so we can fairly compare reps across regions.

with enriched as (
    select * from {{ ref('int_deals_enriched') }}
),

-- first deal date per rep is used as a proxy for tenure start
rep_tenure as (
    select
        sales_agent,
        min(engage_date)    as first_deal_date,
        cast(
            (current_date - min(engage_date)) / 365.0
        as decimal(5,1))    as tenure_years,
        case
            when (current_date - min(engage_date)) < 365  then '0-1 year'
            when (current_date - min(engage_date)) < 730  then '1-2 years'
            when (current_date - min(engage_date)) < 1095 then '2-3 years'
            else '3+ years'
        end                 as tenure_bucket
    from enriched
    group by 1
),

rep_stats as (
    select
        e.sales_agent,
        e.manager,
        e.regional_office,
        t.tenure_years,
        t.tenure_bucket,

        count(*)                                            as total_deals,
        count(case when e.is_won  then 1 end)               as deals_won,
        count(case when e.is_closed and not e.is_won
                   then 1 end)                              as deals_lost,
        count(case when not e.is_closed then 1 end)         as deals_open,

        round(
            100.0 * count(case when e.is_won then 1 end)
                  / nullif(count(case when e.is_closed then 1 end), 0), 1
        )                                                   as win_rate_pct,

        round(sum(case when e.is_won then e.close_value else 0 end), 2)
                                                            as total_revenue,

        round(avg(case when e.is_won then e.close_value end), 2)
                                                            as avg_deal_size,

        round(avg(case when e.is_won then e.days_to_close end), 1)
                                                            as avg_days_to_close,

        -- average account revenue in rep's book — proxy for territory quality
        round(avg(e.account_revenue), 2)                    as avg_territory_account_revenue

    from enriched e
    left join rep_tenure t using (sales_agent)
    group by 1, 2, 3, 4, 5
),

-- territory normalization using window functions
normalized as (
    select
        *,

        -- region average revenue (territory quality benchmark)
        round(avg(total_revenue) over (
            partition by regional_office
        ), 2)                                               as region_avg_revenue,

        -- territory quality index: how rich is this rep's account base vs region avg
        round(
            avg_territory_account_revenue
          / nullif(avg(avg_territory_account_revenue) over (
                partition by regional_office
            ), 0)
        , 3)                                                as territory_quality_index,

        -- raw rank within region (based purely on revenue)
        rank() over (
            partition by regional_office
            order by total_revenue desc
        )                                                   as rank_in_region,

        -- global raw rank
        rank() over (
            order by total_revenue desc
        )                                                   as global_rank_raw,

        -- territory-adjusted performance score
        -- a rep who earns $X in a weak territory scores higher than
        -- a rep who earns $X in a rich territory
        round(
            total_revenue / nullif(
                avg(avg_territory_account_revenue) over (partition by regional_office)
                / nullif(avg(avg_territory_account_revenue) over (), 0)
            , 0)
        , 2)                                                as territory_adjusted_revenue

    from rep_stats
),

final as (
    select
        *,
        rank() over (
            order by territory_adjusted_revenue desc
        )                                                   as global_rank_normalized
    from normalized
)

select * from final
