-- Fails if any closed-won deal has a negative or zero close value.
-- Open deals and lost deals may have zero values, which is valid.

select *
from {{ ref('stg_opportunities') }}
where is_won
  and close_value <= 0
