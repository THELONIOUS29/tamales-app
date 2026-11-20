begin;

-- Preview contains versions of every affected row, so a payment added by
-- another phone after confirmation prevents deleting an unseen collection.
create or replace function public.deletion_preview(p_table text, p_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  business uuid := public.device_owner(); root jsonb; order_ids uuid[];
  order_versions jsonb; payment_versions jsonb; expense_versions jsonb;
  currency_code text; label text; sold bigint; paid bigint; spent bigint;
begin
  if business is null then raise exception 'device_not_authorized'; end if;
  if p_table = 'sales' then
    select jsonb_build_object('id',id,'updated_at',updated_at),currency,
      to_char(sale_date,'DD/MM/YYYY') into root,currency_code,label
      from public.sales where id=p_id and owner_id=business;
  elsif p_table = 'orders' then
    select jsonb_build_object('id',o.id,'updated_at',o.updated_at),s.currency,c.name
      into root,currency_code,label from public.orders o
      join public.sales s on s.id=o.sale_id and s.owner_id=o.owner_id
      join public.clients c on c.id=o.client_id and c.owner_id=o.owner_id
      where o.id=p_id and o.owner_id=business;
  else raise exception 'invalid_delete_table'; end if;
  if root is null then raise exception 'delete_record_not_found'; end if;

  select coalesce(array_agg(id order by id),'{}'::uuid[]),
    coalesce(jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id),'[]'::jsonb),
    coalesce(sum(total_cents),0) into order_ids,order_versions,sold
    from public.orders where owner_id=business and
      ((p_table='sales' and sale_id=p_id) or (p_table='orders' and id=p_id));
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id),'[]'::jsonb),
    coalesce(sum(amount_cents),0) into payment_versions,paid
    from public.payments where owner_id=business and order_id=any(order_ids);
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id),'[]'::jsonb),
    coalesce(sum(amount_cents),0) into expense_versions,spent
    from public.expenses where owner_id=business and p_table='sales' and sale_id=p_id;
  return jsonb_build_object('fingerprint',jsonb_build_object('root',root,
      'orders',order_versions,'payments',payment_versions,'expenses',expense_versions),
    'summary',jsonb_build_object('name',label,'currency',currency_code,
      'orders',cardinality(order_ids),'payments',jsonb_array_length(payment_versions),
      'expenses',jsonb_array_length(expense_versions),'sold_cents',sold,'paid_cents',paid,'spent_cents',spent));
end;
$$;

create or replace function public.delete_business_record(p_table text,p_id uuid,p_expected jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
declare business uuid := public.device_owner(); order_ids uuid[]; current_preview jsonb;
begin
  if business is null then raise exception 'device_not_authorized'; end if;
  if p_table='sales' then
    perform id from public.sales where id=p_id and owner_id=business for update;
  elsif p_table='orders' then
    perform id from public.orders where id=p_id and owner_id=business for update;
  else raise exception 'invalid_delete_table'; end if;
  -- A retry after a lost response is successful without repeating deletions.
  if not found then return; end if;

  -- Root/child row locks also block new FK references until commit. Acquire all
  -- affected locks before deleting anything. No cross-business cascade is used.
  perform id from public.orders where owner_id=business and
    ((p_table='sales' and sale_id=p_id) or (p_table='orders' and id=p_id)) order by id for update;
  select coalesce(array_agg(id),'{}'::uuid[]) into order_ids from public.orders
    where owner_id=business and ((p_table='sales' and sale_id=p_id) or (p_table='orders' and id=p_id));
  perform id from public.payments where owner_id=business and order_id=any(order_ids) order by id for update;
  perform id from public.expenses where owner_id=business and p_table='sales' and sale_id=p_id order by id for update;

  current_preview := public.deletion_preview(p_table,p_id);
  if p_expected is null or current_preview->'fingerprint' is distinct from p_expected then
    raise exception 'delete_graph_changed';
  end if;
  delete from public.payments where owner_id=business and order_id=any(order_ids);
  delete from public.expenses where owner_id=business and p_table='sales' and sale_id=p_id;
  delete from public.orders where owner_id=business and id=any(order_ids);
  if p_table='sales' then delete from public.sales where owner_id=business and id=p_id; end if;
end;
$$;
revoke all on function public.deletion_preview(text,uuid) from public, anon;
revoke all on function public.delete_business_record(text,uuid,jsonb) from public, anon;
grant execute on function public.deletion_preview(text,uuid) to authenticated;
grant execute on function public.delete_business_record(text,uuid,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
