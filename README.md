# Tamales

Aplicación Flutter para pedidos, entregas, cobros, gastos y sincronización con Supabase.

## Sobre esta copia

Instantánea preparada el 20 de noviembre de 2026 para organizar un portafolio profesional. Copia para portafolio. No incluye el historial Git original.

Se omitieron configuraciones locales, credenciales, datos operativos, instalaciones y archivos generados. Los valores `CONFIGURAR_LOCALMENTE`, `CONFIGURAR_TOKEN_LOCALMENTE` y `CONFIGURAR_SECRETO_LOCALMENTE` deben reemplazarse mediante configuración local antes de ejecutar. En scripts SQL se omitieron bloques de datos `INSERT` y `COPY`; en notebooks se borraron salidas guardadas.

El respaldo no constituye una validación de funcionamiento: no se ejecutaron los programas ni sus suites de pruebas durante esta preparación. Dependencias, recursos y configuración pueden requerir restauración. No se añade una licencia nueva ni se atribuyen en exclusiva los trabajos grupales o sus dependencias.

## Documentación del proyecto original

# Tamales

Aplicación Android en Flutter con Supabase. Sin formulario de inicio de sesión.
Todos los teléfonos autorizados acceden a los mismos datos del negocio.

## Estado

- Identidad anónima interna de Supabase, persistida por el SDK en el dispositivo.
- Autorización inicial por instalación, desde el panel de Supabase.
- Inicio: resumen por fecha, cantidades, entregas, cobros, gastos, resultado y acceso a ventas pendientes.
- Clientes: lista, búsqueda local, creación y edición.
- Ventas por fecha: creación y edición, moneda y precios sugeridos.
- Pedidos con cliente guardado, cantidades, precios históricos, observaciones,
  prioridad, disponibilidad y entregado/no entregado.
- Cobros por pedido: abonos, saldo completo, fecha real, método, notas e historial.
- Gastos por venta: importe, descripción opcional, fecha, edición y eliminación.
- Cobros dentro de cada venta, por pedido de cliente, sin depender de la entrega.
- Resumen por venta: cantidades, entregas, vendido, cobrado, pendiente, gastos,
  resultado (vendido menos gastos) y cobrado menos gastos.
- SQLite local: clientes, ventas, pedidos, entregas, cobros y gastos sin conexión.
- Cola persistente y sincronización incremental al recuperar red, volver a la app
  o actualizar. Sin servicio permanente ni Realtime en segundo plano.
- Aviso global de cambios pendientes y revisión de conflictos, dentro de todas
  las pantallas. Los cobros siguen dentro de su venta.
- Reparto con prioridades y horarios, cálculo por calles y notificación de la siguiente entrega.

## Preparación de Supabase

1. En un proyecto nuevo, ejecutar en orden los SQL de `supabase/migrations/`
   en SQL Editor. No repetir los ya instalados. Cada archivo usa una transacción.
2. Activar Anonymous Sign-Ins en Authentication > Sign In / Providers.
3. Abrir la app con internet. Se crea una identidad interna sin pedir correo ni
   contraseña. La app muestra su identificador si aún no está autorizada.
4. Autorizar ese identificador desde SQL Editor usando los ejemplos al final de
   `202610220002_device_access.sql`. El primer teléfono puede ser el propietario
   del negocio; los siguientes deben apuntar a ese MISMO owner_id.
5. Pulsar Reintentar en la app. En siguientes aperturas no se pide activación,
   mientras conserve su sesión y siga autorizado.

Si existen datos anteriores, mantener su owner_id al autorizar dispositivos para
conservar el acceso. No borrar el usuario que sirve de propietario del negocio.
Borrar datos de la app o reinstalar puede requerir una nueva autorización.

La tabla device_access no es accesible desde clientes móviles. Una función con
search_path vacío resuelve únicamente el propietario del dispositivo actual.
Las políticas RLS deniegan acceso a instalaciones no autorizadas y comprueban el
propietario de cada registro. No hay claves secretas ni contraseñas en el APK.
La app no puede registrar dispositivos como autorizados por sí misma.

En el proyecto actual están instaladas las migraciones hasta `202610220006_complete_deletion.sql`. La tercera se aplicó
directamente en SQL Editor y se comprobó con `supabase/tests/financial_checks.sql`.
La prueba usa el dispositivo principal autorizado, crea filas temporales y las
descarta con ROLLBACK. Comprueba abono, reintento idempotente, rechazo de sobrepago,
rechazo de reducción por debajo de lo cobrado, saldo completo y aislamiento de
lectura. No es una prueba de carga ni de dos conexiones simultáneas.
La cuarta también se aplicó en SQL Editor: `sync_checks.sql` verificó descarga
inicial, eventos de creación/edición/eliminación y aislamiento, con ROLLBACK.

## Ejecutar

Existe `config/supabase.local.json` en este equipo y está excluido de Git. En otro
entorno, copiar `config/supabase.example.json` y completar los dos valores.

```powershell
flutter pub get
flutter run --dart-define-from-file=config/supabase.local.json
```

APK de prueba (requiere entorno Android):

```powershell
flutter build apk --debug --dart-define-from-file=config/supabase.local.json
```

APK de distribución de prueba, optimizado y separado por arquitectura (todavía
firmado con la clave de desarrollo; no es una publicación en Play Store):

```powershell
flutter build apk --release --split-per-abi --dart-define-from-file=config/supabase.local.json
```

Gradle usa un máximo de 2 GB de heap, dos trabajadores y compilación Kotlin en
el mismo proceso para ajustar la compilación a este equipo de 8 GB de RAM.

Validación:

```powershell
flutter analyze
flutter test
```

## Sin conexión y consumo

Las lecturas y búsquedas usan SQLite. La primera descarga obtiene una instantánea
coherente de las cinco tablas; después se consultan eventos por cursor, incluidas
eliminaciones. El registro de eventos se serializa por negocio para respetar el
orden de confirmación. La cola conserva UUID, versión base y errores tras reinicios.
Las escrituras condicionales evitan sobrescribir cambios de otro teléfono.

La sincronización se intenta con la app activa, al guardar, recuperar transporte
de red, volver o pedir una actualización. Los fallos usan reintentos espaciados,
sin un servicio en segundo plano. Un conflicto detiene la cola hasta revisarlo.
Ver `docs/offline-sync.md`. No hay mediciones de RAM, batería ni tráfico de red.

## Modelo

Importes en centavos enteros, moneda por venta, precios y dirección históricos
por pedido. Cambiar el precio sugerido no altera pedidos anteriores. Reintentar
una venta/pedido en el mismo formulario usa el mismo UUID y evita duplicarlo.
Las actualizaciones de entrega solo escriben el campo delivered.

Pagos y entregas independientes. Los cobros se registran con la función
`record_payment`, que bloquea el pedido, calcula el saldo actual y reutiliza el
UUID en reintentos. Los triggers también protegen escrituras directas: no admiten
sobrepagos ni reducir el total del pedido por debajo de lo cobrado. La consulta
`pending_balances` calcula las deudas en el servidor y las pagina de 50 en 50.
No hay borrados en cascada. Corregir un cobro erróneo eliminándolo requiere
confirmación en la interfaz y vuelve a calcular el saldo. Las rutas no tienen tablas.

Las pruebas locales cubren ventas/pedidos, precios históricos, entregas, abonos,
saldo completo, pérdidas, gastos y cobro de una deuda anterior. Se simula también
una respuesta perdida después de registrar un cobro para verificar el reintento.
La evidencia de la verificación remota está en `docs/verification/supabase-finances.png`.

La versión 1.0.0+3 se compiló e instaló por actualización
en el teléfono principal, conservando datos y autorización. Se verificó la
apertura de la pantalla Ventas con datos remotos y las tres pestañas. Pasaron
12 pruebas locales y `flutter analyze` sin incidencias. No se registraron cobros
reales durante la verificación; los ensayos de base de datos usaron ROLLBACK.

Versión 1.0.0+4: se retiró la pestaña general Cobros. El acceso a los cobros queda
en Ventas > venta > pedido del cliente > Ver cobros, con fecha de venta visible.

Versión 1.0.0+5: SQLite, cola persistente y sincronización incremental. Compilada
en release ARM64 (aprox. 19.2 MB), instalada conservando los datos y abierta en el
teléfono principal. La primera descarga terminó con estado Sincronizado y la venta
existente visible. Pasaron 20 pruebas y el análisis estático. El canal remoto se
verificó con ROLLBACK; evidencia en `docs/verification/supabase-offline-sync.png`.
La lectura visual del teléfono está en `docs/verification/phone-sync.png`.
La desconexión física de Wi-Fi/datos queda para la prueba manual del usuario;
los ensayos sin red, cierre/reapertura y pérdida de respuesta se automatizaron
con SQLite real y transporte simulado.


## Reparto, ubicación y contacto (versión 1.0.0+6)

- Clientes: ubicación opcional con GPS puntual, coordenadas/enlace expandido o selección en mapa. El mapa se abre solo bajo petición; caché de mosaicos de 32 MiB y sin descargas de zonas. Atribución OpenStreetMap visible.
- Pedidos: dirección, referencia y coordenadas de esa entrega independientes de los datos del cliente. Los cambios del cliente no alteran entregas anteriores.
- Llamar abre el marcador; WhatsApp abre la conversación sin enviar mensajes automáticamente. Navegar abre Google Maps por parada.
- Dentro de cada venta, **Organizar reparto** permite seleccionar pedidos pendientes, punto de salida, hora de salida y minutos por parada. Prioridad alta se atiende primero cuando el cliente está disponible; horarios cerrados generan advertencias de retraso. El orden puede modificarse y una parada se puede dejar al final.
- Cálculo por calles: matriz de tiempos/distancias para automóvil de openrouteservice/HeiGIT. Sin tráfico en vivo. El orden usa una heurística con mejora local acotada; no se promete el óptimo matemático. Hasta 58 pedidos por cálculo por calles, más el origen. Pedidos sin ubicación se enumeran como excluidos, nunca desaparecen silenciosamente.
- Sin internet se puede desactivar **Calcular por calles**: estimación por proximidad, con distancia en línea recta y tiempos aproximados. Las matrices recientes se reutilizan durante 12 horas, incluso para subconjuntos/reordenaciones.
- Un solo reparto activo por teléfono: el itinerario permanece en SQLite de ese teléfono. Ventas, clientes, cobros, gastos y banderas de entrega sí se comparten por Supabase. Otro dispositivo no asume automáticamente el recorrido del repartidor.
- **Iniciar reparto** muestra una notificación Android con siguiente cliente, cantidades, saldo y navegación. No se usa seguimiento GPS de fondo ni un servicio permanente. Marcar Entregado avanza la notificación, manteniendo independiente el pago. Pausar/finalizar retira el aviso. Tras reiniciar Android, abrir la app restaura el reparto; una detención forzada impide actualizar avisos hasta volver a abrirla.
- Android 13+ pide permiso de notificaciones. Si se deniega, el botón **Permisos de notificación** abre los ajustes del sistema. El GPS solo solicita permiso mientras se usa la app, al pulsar el botón correspondiente.
- Eliminación: se permiten pedidos sin cobros, ventas vacías y clientes sin pedidos; se confirma en pantalla y se sincroniza. Los vínculos de la base de datos impiden borrar un registro que recibió nuevos vínculos desde otro teléfono; el conflicto queda en la cola para revisión.

### Servicio de calles

Se desplegó `delivery-matrix` en Supabase y se aplicó `202610220005_route_quota.sql`. El secreto `ORS_API_KEY` se guarda exclusivamente en Edge Function Secrets. No está en el repositorio ni en el APK. La función valida la sesión con `auth.getUser`, comprueba `device_owner`, valida coordenadas y limita el uso a 100 cálculos diarios por negocio. La comprobación de JWT **legacy** del gateway está desactivada para aceptar las claves de firma actuales; la autenticación se realiza explícitamente en la función antes de consultar el proveedor. No hay acceso público al cálculo.

Endpoint vigente: `https://api.heigit.org/openrouteservice/v2/matrix/driving-car`.

Para otra instalación del servidor: aplicar las migraciones por orden, desplegar `supabase/functions/delivery-matrix/index.ts`, configurar `ORS_API_KEY` como secreto y mantener el control de acceso del código. No usar una clave `service_role` en Flutter.

### Verificación de esta entrega

Pruebas unitarias y de interfaz cubren ventas, cobros, gastos, SQLite, reintentos, conflictos, aislamiento, prioridades, horarios, orden manual, matriz asimétrica y más de 20 paradas. Se comprobó además el endpoint desplegado con una identidad temporal autorizada (tiempos y distancias por calles) y sin autorización (403); la identidad temporal fue retirada. `docs/verification/road-matrix.json` contiene únicamente puntos de prueba públicos, sin claves ni datos de clientes.

Los archivos `supabase/tests/delivery_fixture.sql` y `delivery_cleanup.sql` son para QA temporal y **no forman parte de la instalación**. No ejecutarlos en otra cuenta: contienen el propietario de este proyecto y UUID reservados para esa prueba.


## Corrección de eliminación (1.0.0+7)

- El botón de la papelera en la cabecera de una venta está disponible también si tiene pedidos o gastos.
- Eliminar pedido incluye sus cobros, aunque esté entregado y pagado. Eliminar venta completa incluye pedidos, cobros y gastos; los clientes se conservan.
- La confirmación consulta los datos actuales y muestra cantidades e importes. Para preparar esta confirmación se requiere conexión y haber sincronizado los cambios pendientes. Si la conexión se pierde después de confirmar, la eliminación queda en la cola persistente.
- La nueva operación `delete_tree` usa una única transacción SQL, mantiene reintentos idempotentes y comprueba las versiones de todos los registros afectados. Un cambio posterior a la confirmación detiene la eliminación completa y se puede descartar desde el aviso de sincronización para revisar los importes nuevos.
- Aplicada la migración `202610220006_complete_deletion.sql`. Las pruebas reales `supabase/tests/deletion_checks.sql` terminan con ROLLBACK y no modifican ventas reales. Incluyen pedido pagado, venta completa, conservación de cliente, cambio concurrente, reintento y acceso no autorizado.
- Los clientes continúan pudiendo eliminarse solo cuando no tengan pedidos en el historial.


## Pantalla Inicio (1.0.0+8)

La app abre ahora en **Inicio**. La navegación inferior contiene Inicio, Ventas y Clientes. El resumen permite elegir una fecha o volver a Hoy y muestra las cantidades totales por preparar, cantidades por entregar, pedidos entregados, clientes, prioridades pendientes, vendido, cobrado, pendiente de cobro, gastos, resultado y cobrado menos gastos. Agrupa todas las ventas de la fecha sin el límite de paginación de la lista de ventas; las monedas se muestran por separado.

Los importes se atribuyen a la fecha de la venta, aunque el cobro o gasto se haya registrado otro día. Las ventas anteriores con entregas o cobros pendientes y las próximas ventas tienen acceso directo; los cobros permanecen dentro de cada venta. Si el día está vacío, se ofrece seleccionar la próxima fecha programada.

El resumen usa una sola lectura transaccional de SQLite, incluyendo cambios locales y eliminaciones pendientes. No añade consultas de red periódicas ni un servicio nuevo. Se actualiza al guardar/sincronizar, actualizar manualmente o volver a la app; al cambiar de día conserva la opción Hoy si estaba seleccionada. Una fecha elegida manualmente permanece mientras se usa la app.


## Publicación y configuración

Código compartido para portafolio profesional. No incluye credenciales del negocio. Preparación de seguridad del 20 de noviembre de 2026; no equivale a una validación de producción.
