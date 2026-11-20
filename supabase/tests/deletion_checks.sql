-- All inserted and deleted test rows are rolled back. No real sale is touched.
begin;
select set_config('request.jwt.claim.sub','77deb87c-0f5a-4d8c-8c4f-e774ab2cc748',true);
set local role authenticated;
-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.

select public.record_payment('c8c80273-5273-46ce-8574-5fe3cffccd06','c8c80273-5273-46ce-8574-5fe3cffccd03',1000,now(),'cash','',false);

do $checks$
declare preview jsonb; blocked boolean; event_count bigint;
begin
  preview := public.deletion_preview('sales','c8c80273-5273-46ce-8574-5fe3cffccd02');
  if (preview->'summary'->>'orders')::int <> 2 or (preview->'summary'->>'paid_cents')::int <> 1000
     or (preview->'summary'->>'spent_cents')::int <> 200 then raise exception 'FAIL preview'; end if;
  perform public.record_payment('c8c80273-5273-46ce-8574-5fe3cffccd07','c8c80273-5273-46ce-8574-5fe3cffccd04',100,now(),'cash','',false);
  blocked := false;
  begin
    perform public.delete_business_record('sales','c8c80273-5273-46ce-8574-5fe3cffccd02',preview->'fingerprint');
  exception when raise_exception then
    if sqlerrm <> 'delete_graph_changed' then raise; end if;
    blocked := true;
  end;
  if not blocked or not exists(select 1 from public.payments where id='c8c80273-5273-46ce-8574-5fe3cffccd06')
    or not exists(select 1 from public.expenses where id='c8c80273-5273-46ce-8574-5fe3cffccd05') then
    raise exception 'FAIL stale preview must leave all financial records intact'; end if;

  preview := public.deletion_preview('orders','c8c80273-5273-46ce-8574-5fe3cffccd03');
  perform public.delete_business_record('orders','c8c80273-5273-46ce-8574-5fe3cffccd03',preview->'fingerprint');
  if exists(select 1 from public.orders where id='c8c80273-5273-46ce-8574-5fe3cffccd03')
    or exists(select 1 from public.payments where id='c8c80273-5273-46ce-8574-5fe3cffccd06') then raise exception 'FAIL paid order deletion'; end if;
  if not exists(select 1 from public.orders where id='c8c80273-5273-46ce-8574-5fe3cffccd04')
    or not exists(select 1 from public.sales where id='c8c80273-5273-46ce-8574-5fe3cffccd02')
    or not exists(select 1 from public.expenses where id='c8c80273-5273-46ce-8574-5fe3cffccd05') then raise exception 'FAIL order deletion scope'; end if;
  select count(*) into event_count from public.sync_events;
  perform public.delete_business_record('orders','c8c80273-5273-46ce-8574-5fe3cffccd03',preview->'fingerprint');
  if (select count(*) from public.sync_events) <> event_count then raise exception 'FAIL delete retry'; end if;

  perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
  blocked := false;
  begin
    perform public.delete_business_record('sales','c8c80273-5273-46ce-8574-5fe3cffccd02','{}');
  exception when raise_exception then
    if sqlerrm <> 'device_not_authorized' then raise; end if;
    blocked := true;
  end;
  if not blocked then raise exception 'FAIL unauthorized deletion'; end if;
  perform set_config('request.jwt.claim.sub','77deb87c-0f5a-4d8c-8c4f-e774ab2cc748',true);
  preview := public.deletion_preview('sales','c8c80273-5273-46ce-8574-5fe3cffccd02');
  perform public.delete_business_record('sales','c8c80273-5273-46ce-8574-5fe3cffccd02',preview->'fingerprint');
  if exists(select 1 from public.sales where id='c8c80273-5273-46ce-8574-5fe3cffccd02')
    or exists(select 1 from public.orders where sale_id='c8c80273-5273-46ce-8574-5fe3cffccd02')
    or exists(select 1 from public.payments where id='c8c80273-5273-46ce-8574-5fe3cffccd07')
    or exists(select 1 from public.expenses where sale_id='c8c80273-5273-46ce-8574-5fe3cffccd02') then raise exception 'FAIL complete sale deletion'; end if;
  if not exists(select 1 from public.clients where id='c8c80273-5273-46ce-8574-5fe3cffccd01') then raise exception 'FAIL client must remain'; end if;
end;
$checks$;
rollback;
select 'OK: pedido pagado, venta completa, cliente conservado, reintento, cambio concurrente y acceso. Sin cambios permanentes.' as resultado;
