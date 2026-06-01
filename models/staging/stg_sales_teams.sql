with source as (
    select * from {{ ref('sales_teams') }}
),

cleaned as (
    select
        trim(sales_agent)       as sales_agent,
        trim(manager)           as manager,
        trim(regional_office)   as regional_office
    from source
    where sales_agent is not null
)

select * from cleaned
