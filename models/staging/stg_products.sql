with source as (
    select * from {{ ref('products') }}
),

cleaned as (
    select
        trim(product)                           as product,
        trim(series)                            as series,
        cast(sales_price as decimal(12,2))      as sales_price
    from source
    where product is not null
)

select * from cleaned
