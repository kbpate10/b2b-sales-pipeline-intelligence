with source as (
    select * from {{ ref('accounts') }}
),

cleaned as (
    select
        trim(account)                           as account,
        trim(sector)                            as sector,
        cast(year_established as integer)       as year_established,
        cast(revenue as decimal(15,2))          as revenue,
        cast(employees as integer)              as employees,
        trim(office_location)                   as office_location,
        trim(subsidiary_of)                     as subsidiary_of,

        -- account size tier based on employee count
        case
            when employees < 100                then 'SMB'
            when employees between 100 and 999  then 'Mid-Market'
            else                                     'Enterprise'
        end                                     as account_size_tier,

        -- revenue tier
        case
            when revenue < 10000000             then 'Small'
            when revenue between 10000000
                              and 100000000     then 'Medium'
            else                                     'Large'
        end                                     as revenue_tier

    from source
    where account is not null
)

select * from cleaned
