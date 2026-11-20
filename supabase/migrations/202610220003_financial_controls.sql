-- Ejecutar una vez DESPUÉS de las migraciones 001 y 002.
-- Conserva datos existentes; agrega protección concurrente y consultas de cobros.
begin;

create function public.validate_payment_balance() returns trigger
language plpgsql set search_path = '' as $$
declare
  order_total bigint;
  already_paid numeric;
  target_order uuid;
  target_owner uuid;
begin
  if tg_op = 'DELETE' then
    target_order := old.order_id;
    target_owner := old.owner_id;
  else
    target_order := new.order_id;
    target_owner := new.owner_id;
  end if;
  if tg_op = 'UPDATE' then
    if new.order_id <> old.order_id or new.owner_id <> old.owner_id then
      raise exception 'payment_order_immutable' using errcode = '23514';
    end if;
  end if;

  -- Todos los cobros de un pedido se serializan sobre la misma fila.
  select total_cents into order_total from public.orders
    where id = target_order and owner_id = target_owner for update;
  if not found then
    raise exception 'payment_order_not_found' using errcode = '23503';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  select coalesce(sum(amount_cents), 0) into already_paid
    from public.payments where order_id = target_order and id <> new.id;
  if already_paid + new.amount_cents > order_total then
    raise exception 'payment_exceeds_balance' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger validate_payment_balance before insert or update or delete
on public.payments for each row execute function public.validate_payment_balance();

create function public.validate_order_paid_total() returns trigger
language plpgsql set search_path = '' as $$
declare already_paid numeric;
begin
  select coalesce(sum(amount_cents), 0) into already_paid
    from public.payments where order_id = old.id;
  -- total_cents es generado; antes de la escritura se recalcula con cantidades
  -- y precios, sin intentar leer NEW.total_cents en el trigger BEFORE.
  if new.pork_quantity::numeric * new.pork_price_cents +
     new.chicken_quantity::numeric * new.chicken_price_cents < already_paid then
    raise exception 'order_total_below_paid' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger validate_order_paid_total before update
on public.orders for each row execute function public.validate_order_paid_total();

create function public.record_payment(
  p_id uuid, p_order_id uuid, p_amount_cents bigint, p_paid_at timestamptz,
  p_method text, p_notes text, p_settle boolean default false
) returns public.payments
language plpgsql set search_path = '' as $$
declare
  target public.orders;
  existing public.payments;
  already_paid numeric;
  amount_to_record bigint;
begin
  select * into target from public.orders
    where id = p_order_id and owner_id = public.device_owner() for update;
  if not found then raise exception 'payment_order_not_found' using errcode = '42501'; end if;

  -- Un cobro confirmado cuyo resultado no llegó al teléfono se devuelve sin
  -- insertar otra fila, incluso si el saldo actual ya es cero.
  select * into existing from public.payments where id = p_id;
  if found then
    if existing.order_id <> p_order_id then
      raise exception 'payment_identifier_conflict' using errcode = '23514';
    end if;
    return existing;
  end if;

  select coalesce(sum(amount_cents), 0) into already_paid
    from public.payments where order_id = p_order_id;
  if already_paid >= target.total_cents then
    raise exception 'payment_no_balance' using errcode = '23514';
  end if;
  if p_settle then
    amount_to_record := target.total_cents - already_paid;
  else
    amount_to_record := p_amount_cents;
  end if;
  if amount_to_record is null or amount_to_record <= 0 then
    raise exception 'payment_invalid_amount' using errcode = '23514';
  end if;
-- Datos INSERT omitidos para portafolio.

  return existing;
end;
$$;
revoke all on function public.record_payment(uuid, uuid, bigint, timestamptz, text, text, boolean) from public, anon;
grant execute on function public.record_payment(uuid, uuid, bigint, timestamptz, text, text, boolean) to authenticated;

create function public.pending_balances(p_offset integer default 0, p_limit integer default 50)
returns table (
  order_id uuid, sale_id uuid, client_name text, sale_date date, currency text,
  total_cents bigint, paid_cents bigint, balance_cents bigint, delivered boolean
)
language sql stable set search_path = '' as $$
  select o.id, o.sale_id, c.name, s.sale_date, s.currency,
         o.total_cents, p.paid, (o.total_cents - p.paid)::bigint, o.delivered
  from public.orders o
  join public.clients c on c.id = o.client_id and c.owner_id = o.owner_id
  join public.sales s on s.id = o.sale_id and s.owner_id = o.owner_id
  cross join lateral (
    select coalesce(sum(amount_cents), 0)::bigint as paid
    from public.payments where order_id = o.id
  ) p
  where o.total_cents > p.paid
  order by s.sale_date, c.name, o.id
  offset greatest(p_offset, 0) limit least(greatest(p_limit, 1), 100);
$$;
revoke all on function public.pending_balances(integer, integer) from public, anon;
grant execute on function public.pending_balances(integer, integer) to authenticated;

notify pgrst, 'reload schema';
commit;
