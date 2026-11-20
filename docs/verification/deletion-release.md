# Corrección de eliminaciones — 1.0.0+7

- APK release arm64 instalado correctamente en HONOR DNP_NX9. Android confirma versionCode 2007.
- Flutter analyze sin incidencias; 32 pruebas de app aprobadas.
- Migración 202610220006_complete_deletion.sql aplicada en Supabase.
- Prueba real deletion_checks.sql aprobada: pedido pagado, venta completa, conservación de cliente, cambio concurrente, reintento y control de acceso; termina con ROLLBACK.
- En el teléfono se abrieron las confirmaciones reales de la venta 23/10/2026 y del pedido Pantera. Ambas mostraron el cobro de USD 5.00 y se cancelaron. No se eliminaron datos reales.
- Capturas: phone-delete-sale.png y phone-delete-order.png. La captura del navegador no estuvo disponible por un timeout del navegador; el resultado SQL aprobado se verificó en su tabla de resultados.
- Las eliminaciones se confirman con los importes actuales. Se necesita conexión para preparar esa confirmación; una pérdida de conexión posterior mantiene una operación atómica persistente pendiente de sincronizar.
