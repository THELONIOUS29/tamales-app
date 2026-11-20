# Tamales: alcance acordado

Aplicación Android ligera con Flutter y Supabase. Un solo negocio compartido en
varios dispositivos, sin formulario de sesión, y una sola ruta por venta.
Cada instalación mantiene una identidad interna y se autoriza una sola vez.

## Modelo de datos previsto

- Clientes: nombre, teléfono internacional, dirección, referencia, coordenadas
  y observaciones. Se reutilizan entre ventas.
- Ventas: fecha de entrega, nombre opcional y precios sugeridos de chancho y pollo.
- Pedidos: venta, cliente, cantidades, precios históricos, observaciones,
  entregado, prioridad alta y disponibilidad opcional desde/hasta una hora.
  La dirección de entrega se conserva en el pedido para no cambiar el historial
  cuando se modifica un cliente.
- Pagos: pedido, importe, fecha real del cobro y método opcional. Se admiten
  abonos; el saldo se calcula sin depender de la entrega.
- Gastos: venta, importe, fecha y descripción opcional.
- Rutas: venta, punto de salida y paradas ordenadas. Selección de pedidos por
  salida, sin gestión de repartidores. Posponer no significa entregar.

Los importes se almacenarán en unidades monetarias mínimas enteras para evitar
errores de redondeo. La moneda se configurará antes de registrar ventas reales.
El resultado de la venta es vendido menos gastos; cobrado menos gastos se
mostrará por separado. Los pagos posteriores siguen asociados a la venta original.

## Orden de implementación

1. Esquema de Supabase, restricciones y autorización inicial de dispositivos.
2. Apertura directa y clientes: crear, editar, buscar y reutilizar.
3. Ventas por fecha y pedidos con precios históricos.
4. Abonos, pendientes de cobro, gastos y resumen calculado.
5. Sincronización entre dispositivos y manejo de errores de conexión.
6. Entregas, llamada, WhatsApp y navegación a cada cliente.
7. Optimización de ruta con prioridades y disponibilidad, y notificación del
   siguiente pedido. Elegir proveedor y revisar sus costos antes de integrarlo.
8. Cola local de cambios sin conexión con identificadores únicos para evitar
   duplicar cobros al reintentar. No prometer sincronización sin conexión hasta
   implementar y probar este comportamiento.

## Conexión

La URL y la clave publicable están configuradas localmente. Las cuatro migraciones
están aplicadas; Anonymous Sign-Ins está activo y el teléfono principal autorizado.
Los nuevos teléfonos deben autorizarse con el mismo propietario del negocio.
Se usa Supabase Auth internamente, sin correo ni contraseña.
Las políticas RLS solo admiten los dispositivos autorizados. No incluir claves
secretas ni service_role en la aplicación.

## Estado inicial

Estructura Flutter para Android, identificación interna sin formulario y pantallas
para listar, buscar, crear y editar clientes. Las búsquedas son locales y al volver
a la app se intenta una sincronización incremental, sin recargar tablas completas.
El servicio de autenticación remoto respondió a la comprobación de conectividad.
El usuario confirmó el guardado de clientes en el teléfono principal.
Ventas por fecha y pedidos ya tienen pantallas de
creación y edición, resumen de cantidades y total vendido, prioridad, horario y
entregado/no entregado. Se conservan precio y dirección históricos.
Cobros, abonos y gastos tienen pantallas e historial. El resumen financiero separa
vendido, cobrado, deuda, gastos y resultado. Los cobros se gestionan dentro de
cada venta, desde el pedido de cada cliente; no hay pestaña general de cobros.
Las reglas de saldo y reintentos están comprobadas en Supabase
con filas temporales y ROLLBACK. Rutas y notificaciones quedan pendientes.
SQLite, cola persistente y sincronización incremental están implementados. Las
pruebas cubren cierre/reapertura, relaciones, pagos con respuestas perdidas,
conflictos, eliminaciones y autorización revocada. La primera apertura en cada
instalación sigue requiriendo internet para autorizar y descargar el negocio.
Sincroniza con la app activa; no se agregó un servicio permanente. Todavía no hay
mediciones de consumo.
