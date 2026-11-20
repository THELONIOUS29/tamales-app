begin;
delete from public.orders where id in ('eeeeeeee-2222-4444-8888-000000000301','eeeeeeee-2222-4444-8888-000000000302') and owner_id='77deb87c-0f5a-4d8c-8c4f-e774ab2cc748';
delete from public.sales where id='eeeeeeee-2222-4444-8888-000000000201' and owner_id='77deb87c-0f5a-4d8c-8c4f-e774ab2cc748' and title='PRUEBA TEMPORAL DE REPARTO';
delete from public.clients where id in ('eeeeeeee-2222-4444-8888-000000000101','eeeeeeee-2222-4444-8888-000000000102') and owner_id='77deb87c-0f5a-4d8c-8c4f-e774ab2cc748' and name like 'PRUEBA REPARTO %';
commit;
