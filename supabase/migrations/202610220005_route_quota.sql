begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.route_quota (
  owner_id uuid not null references auth.users(id),
  day date not null,
  requests integer not null default 0,
  primary key(owner_id, day)
);
alter table private.route_quota enable row level security;
revoke all on private.route_quota from public, anon, authenticated;

create or replace function public.reserve_route_request()
returns boolean language plpgsql security definer set search_path = '' as $$
declare business uuid; used integer;
begin
  business := public.device_owner();
  if business is null then raise exception 'unauthorized'; end if;
-- Datos INSERT omitidos para portafolio.

  return used is not null;
end;
$$;
revoke all on function public.reserve_route_request() from public, anon;
grant execute on function public.reserve_route_request() to authenticated;
notify pgrst, 'reload schema';
commit;
