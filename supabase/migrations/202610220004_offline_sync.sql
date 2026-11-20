-- Registro incremental: solo se descargan cambios nuevos y eliminaciones.
begin;
create table public.sync_events (
  sequence bigint generated always as identity primary key,
  owner_id uuid not null references auth.users(id),
  table_name text not null check (table_name in ('clients','sales','orders','payments','expenses')),
  record_id uuid not null,
  record_data jsonb,
  occurred_at timestamptz not null default now()
);
create index sync_events_owner_sequence on public.sync_events(owner_id,sequence);
alter table public.sync_events enable row level security;
revoke all on public.sync_events from anon, authenticated;
grant select on public.sync_events to authenticated;
create policy device_read on public.sync_events for select to authenticated
  using (owner_id = (select public.device_owner()));

create function public.capture_sync_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare business uuid; record uuid; contents jsonb;
begin
  if tg_op = 'DELETE' then
    business := old.owner_id; record := old.id; contents := null;
  else
    business := new.owner_id; record := new.id; contents := to_jsonb(new);
  end if;
  -- Se asigna la secuencia después de obtener este bloqueo por negocio, que se
  -- conserva hasta COMMIT. Así un cambio no puede confirmar después de otro
  -- con secuencia mayor y perderse al avanzar el cursor de un teléfono.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(business::text, 19027));
-- Datos INSERT omitidos para portafolio.

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.capture_sync_event() from public, anon, authenticated;

do $setup$
declare table_name text;
begin
  foreach table_name in array array['clients','sales','orders','payments','expenses'] loop
    execute format('create trigger capture_sync_event after insert or update or delete on public.%I for each row execute function public.capture_sync_event()',table_name);
  end loop;
end;
$setup$;

create function public.sync_bootstrap() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'cursor',coalesce((select max(sequence) from public.sync_events where owner_id = (select public.device_owner())),0),
    'tables',jsonb_build_object(
      'clients',coalesce((select jsonb_agg(to_jsonb(c)) from public.clients c where owner_id = (select public.device_owner())),'[]'::jsonb),
      'sales',coalesce((select jsonb_agg(to_jsonb(s)) from public.sales s where owner_id = (select public.device_owner())),'[]'::jsonb),
      'orders',coalesce((select jsonb_agg(to_jsonb(o)) from public.orders o where owner_id = (select public.device_owner())),'[]'::jsonb),
      'payments',coalesce((select jsonb_agg(to_jsonb(p)) from public.payments p where owner_id = (select public.device_owner())),'[]'::jsonb),
      'expenses',coalesce((select jsonb_agg(to_jsonb(e)) from public.expenses e where owner_id = (select public.device_owner())),'[]'::jsonb)
    )
  );
$$;
revoke all on function public.sync_bootstrap() from public, anon;
grant execute on function public.sync_bootstrap() to authenticated;

create function public.sync_changes(p_after bigint default 0,p_limit integer default 500)
returns setof public.sync_events language sql stable set search_path = '' as $$
  select * from public.sync_events
  where owner_id = (select public.device_owner()) and sequence > greatest(p_after,0)
  order by sequence limit least(greatest(p_limit,1),500);
$$;
revoke all on function public.sync_changes(bigint,integer) from public, anon;
grant execute on function public.sync_changes(bigint,integer) to authenticated;
notify pgrst,'reload schema';
commit;
