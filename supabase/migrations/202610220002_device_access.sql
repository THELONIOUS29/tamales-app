-- Ejecutar DESPUÉS de 202610220001_initial.sql, incluso si aún no hay usuarios.
-- El administrador autoriza instalaciones desde SQL Editor. Ningún dispositivo
-- puede autorizarse a sí mismo ni escoger el negocio al que accede.
begin;

create table public.device_access (
  device_id uuid primary key references auth.users(id),
  owner_id uuid not null references auth.users(id),
  label text not null default '',
  created_at timestamptz not null default now()
);
alter table public.device_access enable row level security;
revoke all on public.device_access from anon, authenticated;

create function public.device_owner() returns uuid
language sql stable security definer set search_path = '' as $$
  select owner_id from public.device_access where device_id = (select auth.uid());
$$;
revoke all on function public.device_owner() from public, anon;
grant execute on function public.device_owner() to authenticated;

do $$
declare table_name text;
begin
  foreach table_name in array array['clients', 'sales', 'orders', 'payments', 'expenses'] loop
    execute format('drop policy owner_access on public.%I', table_name);
    execute format(
      'create policy device_access on public.%I for all to authenticated using (owner_id = (select public.device_owner())) with check (owner_id = (select public.device_owner()))',
      table_name
    );
    execute format('alter table public.%I alter column owner_id set default public.device_owner()', table_name);
  end loop;
end;
$$;
commit;

-- Autorizar primer teléfono (sustituir UUID_PRIMER_TELEFONO por el identificador
-- que muestra la app). Si ya hay datos, usar el owner_id ORIGINAL de esos datos
-- en el segundo campo, en lugar del UUID del primer teléfono.
-- insert into public.device_access (device_id, owner_id, label)
-- values ('UUID_PRIMER_TELEFONO', 'UUID_PRIMER_TELEFONO', 'Principal');

-- Autorizar otro teléfono con EL MISMO owner_id del primero:
-- insert into public.device_access (device_id, owner_id, label)
-- values ('UUID_OTRO_TELEFONO', 'UUID_PRIMER_TELEFONO', 'Segundo teléfono');

-- Revocar un teléfono: delete from public.device_access where device_id = 'UUID';
