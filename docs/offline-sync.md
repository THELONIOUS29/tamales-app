# Guardado local y sincronización

## Comportamiento

El teléfono autorizado abre una base SQLite por negocio. Guarda tanto la última
versión recibida de Supabase como las operaciones pendientes, en transacciones.
Las pantallas leen una vista que superpone esas operaciones a los datos remotos.
Guardar en la interfaz confirma el guardado local; la barra indica si se envió.

La sesión de Supabase se restaura del teléfono y se recuerda el negocio autorizado
para abrir sin internet. Al conectar, se vuelve a verificar la autorización. Una
revocación conocida se persiste y bloquea la interfaz y las escrituras incluso
tras reiniciar. Una revocación remota no puede conocerse mientras no hay conexión.

## Transferencias

La descarga inicial es una instantánea de clientes, ventas, pedidos, cobros y
gastos con su cursor. Las siguientes descargas piden solo eventos nuevos, en
páginas de 500. Las eliminaciones también tienen eventos. Los eventos pertenecen
al negocio y aplican RLS; las tablas no se exponen a otros dispositivos.

Se sincroniza en primer plano al guardar, recuperar red, regresar o actualizar.
No se añadió servicio permanente. Si hay transporte pero no responde Supabase,
los intentos se espacian 5, 15, 45 y 120 segundos. Al salir se cancela el siguiente
intento; una petición ya iniciada puede terminar. No se envían fotos ni mapas.

## Consistencia

La cola conserva el orden: cliente y venta antes de pedido, y pedido antes de
cobro. Los UUID se reutilizan. Los cobros usan la función idempotente instalada
en Supabase y conservan el importe recibido aunque el saldo remoto haya cambiado.
La opción de saldo completo fija el saldo local: no reduce silenciosamente un
importe recibido para ajustarlo al servidor.

Los cambios de registros existentes comprueban updated_at. Si otro dispositivo
los modificó, se conserva el cambio local y se pide revisión. Una respuesta
perdida se reconoce si el servidor ya contiene los campos enviados. En casos
ambiguos, una operación posterior puede pedir revisión antes de sobrescribir.

Un cobro rechazado permanece en el historial como pendiente de revisión y no se
suma al resumen como importe aceptado. La cola se detiene en el primer conflicto
para no enviar registros dependientes. Reintentar conserva el mismo identificador;
descartar solo retira esa operación local y deja la versión de Supabase.

## Alcance de las pruebas

SQLite real en archivo temporal: reinicio con operaciones pendientes, creación
encadenada, cobro cuya respuesta se pierde tras confirmar, conflicto de saldo,
ediciones concurrentes, eliminaciones y revocación persistente. Las pruebas de
widgets verifican guardado sin red y etiquetas provisionales. Supabase se probó
con filas temporales y ROLLBACK para los eventos y el aislamiento.

No se han medido autonomía ni volumen de datos. Los eventos no tienen purga
automática. La primera descarga requiere internet y puede crecer con el historial.
Los cambios pendientes permanecen solo en ese teléfono hasta sincronizar.
