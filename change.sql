with catalogue as (
    select 
        partner_code, 
        sku_name, 
        price/100 as discount
    from VITALITY_PARTNER.PARTNER_CATALOGUE_V
    where getdate() between effective_from and effective_to
      and sku_status = 'ACTIVE'
      and tenant_id = 9
      and (
          (partner_code = 'EVERRISE' and sku_name in (
              'EVERRISEBASEBRZE','EVERRISEBASEGOLD','EVERRISEBASEPLAT','EVERRISEBASESLVR',
              'EVERRISEVHCBRZE','EVERRISEVHCGOLD','EVERRISEVHCPLAT','EVERRISEVHCSLVR',
              'EVERRISEVHRBRZE','EVERRISEVHRGOLD','EVERRISEVHRPLAT','EVERRISEVHRSLVR'
          ))
          or partner_code in ('JAYAGROCERYMY','VHCM')
      )
),
transactions_monthly as (
    select 
        partner_code, 
        entity_num, 
        sum(qualifying_amt) as total_amt
    from vitality_partner.partner_transaction_v
    where partner_code in ('JAYAGROCERYMY','VHCM','EVERRISE')
      and transaction_status = 'COMPLETED'
      and transaction_date between dateadd(day,1,eomonth(getdate(),-1)) and eomonth(getdate())
    group by partner_code, entity_num
),
transactions_yesterday as (
    select distinct
        pt.entity_num,
        pt.partner_code
    from vitality_partner.partner_transaction_v pt
    where pt.partner_code in ('JAYAGROCERYMY','VHCM','EVERRISE')
      and pt.transaction_status = 'COMPLETED'
      and pt.processed_dttm between cast(getdate()-1 as date) and cast(getdate() as date)
)
select
    eon.entity_other_no as AIA_MEMBER_ID,
    case when epc.eff_to < getdate() then 'I' else 'A' end as STATUS,
    cat.discount as VITALITY_DISCOUNT_PERCENTAGE,
    (400 - coalesce(tm.total_amt,0)) as REMAINING_LIMIT
from fv_core.entity_policy_conn_hist_v epc
join fv_core.entity_other_nos_v eon
    on eon.entity_no = epc.entity_no 
   and eon.no_type='AMN'
left join transactions_monthly tm
    on tm.entity_num = epc.entity_no
left join catalogue cat
    on cat.partner_code = tm.partner_code
where epc.entity_role='PP'
  and epc.tenant_id=9
  and epc.eff_to >= dateadd(day,-365,getdate())
  and exists (
      select 1 from transactions_yesterday ty
      where ty.entity_num = epc.entity_no
  );
