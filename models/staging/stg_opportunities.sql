with source as (
    select * from {{ ref('sales_pipeline') }}
),

cleaned as (
    select
        opportunity_id,
        trim(sales_agent)                               as sales_agent,
        trim(product)                                   as product,
        trim(account)                                   as account,
        trim(deal_stage)                                as deal_stage,
        cast(engage_date as date)                       as engage_date,
        cast(close_date as date)                        as close_date,
        cast(coalesce(close_value, 0) as decimal(12,2)) as close_value,

        -- derived flags
        case
            when deal_stage in ('Won', 'Lost') then true
            else false
        end                                             as is_closed,

        case
            when deal_stage = 'Won' then true
            else false
        end                                             as is_won,

        -- days to close (null for open deals)
        case
            when deal_stage in ('Won', 'Lost')
            then cast(close_date - engage_date as integer)
        end                                             as days_to_close,

        -- stage ordering for funnel analysis
        case deal_stage
            when 'Prospecting' then 1
            when 'Engaging'    then 2
            when 'Won'         then 3
            when 'Lost'        then 3
            else 0
        end                                             as stage_order

    from source
    where opportunity_id is not null
)

select * from cleaned
