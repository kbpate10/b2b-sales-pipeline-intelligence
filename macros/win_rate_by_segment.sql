{% macro win_rate_by_segment(relation, group_by_col) %}

select
    {{ group_by_col }},
    count(*)                                            as total_closed,
    sum(case when is_won then 1 else 0 end)             as won,
    round(
        100.0 * sum(case when is_won then 1 else 0 end)
              / nullif(count(*), 0), 1
    )                                                   as win_rate_pct
from {{ relation }}
where is_closed
group by 1
order by win_rate_pct desc

{% endmacro %}
