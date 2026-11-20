-- Prueba transaccional: todas las filas creadas se descartan con ROLLBACK.
-- Ajustar solo el UUID del dispositivo autorizado para otro proyecto.
begin;
select set_config('request.jwt.claim.sub', '77deb87c-0f5a-4d8c-8c4f-e774ab2cc748', true);
set local role authenticated;
-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.


do $checks$
declare blocked boolean;
begin
  perform public.record_payment('b8c80273-5273-46ce-8574-5fe3cffccd04', 'b8c80273-5273-46ce-8574-5fe3cffccd03', 400, now(), 'cash', '', false);
  perform public.record_payment('b8c80273-5273-46ce-8574-5fe3cffccd04', 'b8c80273-5273-46ce-8574-5fe3cffccd03', 400, now(), 'cash', '', false);
  if (select count(*) from public.payments where order_id = 'b8c80273-5273-46ce-8574-5fe3cffccd03') <> 1 then raise exception 'FAIL duplicate retry'; end if;
  if not exists(select 1 from public.pending_balances(0,100) where order_id = 'b8c80273-5273-46ce-8574-5fe3cffccd03' and balance_cents = 600 and delivered) then raise exception 'FAIL delivered debt'; end if;

  blocked := false;
  begin
    perform public.record_payment('b8c80273-5273-46ce-8574-5fe3cffccd05', 'b8c80273-5273-46ce-8574-5fe3cffccd03', 700, now(), 'cash', '', false);
  exception when check_violation then
    if sqlerrm <> 'payment_exceeds_balance' then raise; end if;
    blocked := true;
  end;
  if not blocked then raise exception 'FAIL overpayment accepted'; end if;

  blocked := false;
  begin
    update public.orders set pork_quantity = 3 where id = 'b8c80273-5273-46ce-8574-5fe3cffccd03';
  exception when check_violation then
    if sqlerrm <> 'order_total_below_paid' then raise; end if;
    blocked := true;
  end;
  if not blocked then raise exception 'FAIL price reduction accepted'; end if;

  perform public.record_payment('b8c80273-5273-46ce-8574-5fe3cffccd06', 'b8c80273-5273-46ce-8574-5fe3cffccd03', null, now(), 'transfer', '', true);
  if (select sum(amount_cents) from public.payments where order_id = 'b8c80273-5273-46ce-8574-5fe3cffccd03') <> 1000 then raise exception 'FAIL settlement amount'; end if;
  if exists(select 1 from public.pending_balances(0,100) where order_id = 'b8c80273-5273-46ce-8574-5fe3cffccd03') then raise exception 'FAIL settled debt remains'; end if;
end;
$checks$;

select set_config('request.jwt.claim.sub', 'b8c80273-5273-46ce-8574-5fe3cffccd09', true);
do $checks$
begin
  if exists(select 1 from public.orders where id = 'b8c80273-5273-46ce-8574-5fe3cffccd03') then raise exception 'FAIL unauthorized device can read'; end if;
end;
$checks$;
rollback;
select case when not exists(select 1 from public.clients where id = 'b8c80273-5273-46ce-8574-5fe3cffccd01')
  then 'OK: abono, reintento, limites, saldo completo y aislamiento. Datos de prueba descartados.'
  else 'ERROR: quedaron datos de prueba' end as resultado;
