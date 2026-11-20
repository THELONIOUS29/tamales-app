-- Ejecutar una vez en SQL Editor de Supabase, sobre un proyecto nuevo.
begin;

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id),
  name text not null check (length(trim(name)) > 0),
  phone text not null default '',
  address text not null default '',
  reference text not null default '',
  notes text not null default '',
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id),
  check ((latitude is null) = (longitude is null))
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id),
  sale_date date not null,
  title text not null default '',
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  pork_price_cents bigint not null check (pork_price_cents >= 0),
  chicken_price_cents bigint not null check (chicken_price_cents >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id),
  sale_id uuid not null,
  client_id uuid not null,
  pork_quantity integer not null default 0 check (pork_quantity >= 0),
  chicken_quantity integer not null default 0 check (chicken_quantity >= 0),
  pork_price_cents bigint not null check (pork_price_cents >= 0),
  chicken_price_cents bigint not null check (chicken_price_cents >= 0),
  total_cents bigint generated always as
    (pork_quantity::bigint * pork_price_cents + chicken_quantity::bigint * chicken_price_cents) stored,
  delivered boolean not null default false,
  high_priority boolean not null default false,
  available_from time,
  available_until time,
  delivery_address text not null default '',
  delivery_reference text not null default '',
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id),
  foreign key (sale_id, owner_id) references public.sales(id, owner_id),
  foreign key (client_id, owner_id) references public.clients(id, owner_id),
  check (pork_quantity > 0 or chicken_quantity > 0),
  check ((latitude is null) = (longitude is null)),
  check (available_from is null or available_until is null or available_until >= available_from)
);

create table public.payments (
  -- El dispositivo debe generar y reutilizar el mismo UUID al reintentar un cobro.
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id),
  order_id uuid not null,
  amount_cents bigint not null check (amount_cents > 0),
  paid_at timestamptz not null default now(),
  method text check (method in ('cash', 'transfer', 'other')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (order_id, owner_id) references public.orders(id, owner_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id),
  sale_id uuid not null,
  amount_cents bigint not null check (amount_cents > 0),
  description text not null default '',
  spent_on date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (sale_id, owner_id) references public.sales(id, owner_id)
);

create index clients_owner_name_idx on public.clients(owner_id, name);
create index sales_owner_date_idx on public.sales(owner_id, sale_date);
create index orders_owner_sale_idx on public.orders(owner_id, sale_id);
create index orders_client_idx on public.orders(client_id, owner_id);
create index payments_owner_order_idx on public.payments(owner_id, order_id);
create index expenses_owner_sale_idx on public.expenses(owner_id, sale_id);

create function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array['clients', 'sales', 'orders', 'payments', 'expenses'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
    execute format(
      'create policy owner_access on public.%I for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))',
      table_name
    );
    execute format(
      'create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      table_name
    );
  end loop;
end;
$$;
commit;
