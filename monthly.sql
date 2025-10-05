select 
    eon.entity_other_no as AIA_MEMBER_ID,
    case when epc.eff_to < getdate() then 'T' else 'A' end as STATUS,

    (
        select 
            case 
                when sum(qualifying_amt) is null then 
                    (
                        select price/100 
                        from VITALITY_PARTNER.PARTNER_CATALOGUE_V 
                        where partner_code = 'EVERRISE'
                          and sku_name in (
                              'EVERRISEBASEBRZE','EVERRISEBASEGOLD','EVERRISEBASEPLAT','EVERRISEBASESLVR',
                              'EVERRISEVHCBBRZE','EVERRISEVHCGOLD','EVERRISEVHCCPLAT','EVERRISEVHCSLVR',
                              'EVERRISEVHRBRZE','EVERRISEVHRGOLD','EVERRISEVHRPLAT','EVERRISEVHRSLVR'
                          )
                          and getdate() between effective_from and effective_to
                          and sku_status = 'ACTIVE'
                          and tenant_id = 9
                    )
                else 
                    (
                        select price/100 
                        from VITALITY_PARTNER.PARTNER_CATALOGUE_V 
                        where partner_code in ('JAYAGROCERYMY','VHCM','EVERRISE')
                          and getdate() between effective_from and effective_to
                          and sku_status = 'ACTIVE'
                          and tenant_id = 9
                    )
            end
    ) as VITALITY_DISCOUNT_PERCENTAGE,

    400 as REMAINING_LIMIT

from fv_core.entity_policy_conn_hist_v epc
join fv_core.entity_other_nos_v eon
    on eon.entity_no = epc.entity_no 
   and eon.no_type = 'AMN'
where epc.entity_role = 'PP'
  and epc.tenant_id = 9
  and epc.eff_to >= dateadd(day, -365, getdate())
  and getdate() between epc.eff_from and epc.eff_to
  and cast(getdate() - 1 as date) between eon.eff_from and eon.eff_to
  and exists (
      select 1
      from vitality_partner.partner_transaction_v pt
      where pt.entity_num = epc.entity_no
        and pt.partner_code in ('JAYAGROCERYMY','VHCM','EVERRISE')
        and pt.transaction_status = 'COMPLETED'
        and pt.transaction_date between dateadd(month,-12,getdate()) and getdate()
  );
