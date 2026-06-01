with opportunities as (
    select * from {{ ref('stg_opportunities') }}
),

accounts as (
    select * from {{ ref('stg_accounts') }}
),

teams as (
    select * from {{ ref('stg_sales_teams') }}
),

products as (
    select * from {{ ref('stg_products') }}
),

enriched as (
    select
        -- opportunity core
        o.opportunity_id,
        o.sales_agent,
        o.product,
        o.account,
        o.deal_stage,
        o.engage_date,
        o.close_date,
        o.close_value,
        o.is_closed,
        o.is_won,
        o.days_to_close,
        o.stage_order,

        -- team dimensions
        t.manager,
        t.regional_office,

        -- account dimensions
        a.sector,
        a.year_established,
        a.revenue             as account_revenue,
        a.employees,
        a.account_size_tier,
        a.revenue_tier,
        a.office_location,

        -- product dimensions
        p.series              as product_series,
        p.sales_price         as product_list_price,

        -- deal age for open deals (how long has this been sitting in pipeline)
        case
            when not o.is_closed
            then cast(current_date - o.engage_date as integer)
        end                   as open_deal_age_days,

        -- stalled flag: open deals older than 30 days
        case
            when not o.is_closed
             and cast(current_date - o.engage_date as integer) > 30
            then true
            else false
        end                   as is_stalled,

        -- cohort month (month deal entered pipeline)
        strftime(o.engage_date, '%Y-%m')  as engage_cohort_month,

        -- close month (for won deals)
        case
            when o.is_won
            then strftime(o.close_date, '%Y-%m')
        end                               as close_cohort_month

    from opportunities o
    left join teams    t on o.sales_agent = t.sales_agent
    left join accounts a on o.account     = a.account
    left join products p on o.product     = p.product
)

select * from enriched
