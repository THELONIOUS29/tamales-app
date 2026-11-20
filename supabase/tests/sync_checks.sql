-- Prueba del canal incremental con filas temporales, sin cambios persistentes.
begin;
select set_config('request.jwt.claim.sub','77deb87c-0f5a-4d8c-8c4f-e774ab2cc748',true);
set local role authenticated;
do $checks$
declare initial_cursor bigint; snapshot jsonb; count_events integer;
begin
  select coalesce(max(sequence),0) into initial_cursor from public.sync_events;
-- Datos INSERT omitidos para portafolio.

  snapshot := public.sync_bootstrap();
  if not exists(select 1 from jsonb_array_elements(snapshot->'tables'->'clients') row
    where row->>'id' = 'b8c80273-5273-46ce-8574-5fe3cffcdd01') then
    raise exception 'FAIL bootstrap omits client';
  end if;
  update public.clients set name='Prueba actualizada' where id='b8c80273-5273-46ce-8574-5fe3cffcdd01';
  delete from public.clients where id='b8c80273-5273-46ce-8574-5fe3cffcdd01';
  select count(*) into count_events from public.sync_changes(initial_cursor,500)
    where record_id='b8c80273-5273-46ce-8574-5fe3cffcdd01';
  if count_events <> 3 then raise exception 'FAIL incremental create/update/delete'; end if;
  if not exists(select 1 from public.sync_changes(initial_cursor,500)
    where record_id='b8c80273-5273-46ce-8574-5fe3cffcdd01' and record_data is null) then
    raise exception 'FAIL missing deletion event';
  end if;
end;
$checks$;
select set_config('request.jwt.claim.sub','b8c80273-5273-46ce-8574-5fe3cffcdd09',true);
do $checks$
begin
  if exists(select 1 from public.sync_changes(0,500)) then raise exception 'FAIL unauthorized events'; end if;
  if jsonb_array_length(public.sync_bootstrap()->'tables'->'clients') <> 0 then raise exception 'FAIL unauthorized bootstrap'; end if;
end;
$checks$;
rollback;
select 'OK: descarga inicial, cambios, eliminaciones y aislamiento. Prueba descartada.' as resultado;
