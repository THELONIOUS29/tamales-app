# CÃ³mo usar la versiÃ³n actual

## Inicio

La app abre en Inicio. El botÃ³n de calendario permite elegir la fecha del resumen;
Hoy vuelve al dÃ­a actual. Se muestran las cantidades por preparar y entregar,
pedidos entregados, clientes, vendido, cobrado, pendiente, gastos y resultado de
todas las ventas de esa fecha. Cada moneda aparece por separado.

Si no hay ventas hoy, toca Ver prÃ³xima fecha para consultar la siguiente venta
programada. Las ventas anteriores con entregas o cobros pendientes tambiÃ©n tienen
acceso directo. Toca una venta para gestionar sus pedidos, cobros o gastos.

El resumen se puede consultar sin internet y se actualiza al guardar o sincronizar.
Los importes corresponden a las ventas de la fecha elegida, aunque un cobro o gasto
se haya registrado otro dÃ­a. Los cobros siguen dentro de cada venta.

## Clientes

En la pestaÃ±a Clientes, agrega el nombre, telÃ©fono, direcciÃ³n y referencias.
Toca un cliente guardado para editarlo. Se reutiliza en las siguientes ventas.

## Crear una venta

En Ventas, toca Nueva venta. Elige la fecha de entrega y los precios unitarios de
chancho y pollo. Puedes poner un nombre opcional. USD significa dÃ³lares; si
trabajas en otra moneda, cambia su cÃ³digo al crear la venta.

## Agregar pedidos

Abre la venta y toca Agregar pedido. Selecciona un cliente guardado; puedes buscar
por nombre o telÃ©fono. Indica las cantidades. El total se calcula automÃ¡ticamente.
Puedes ajustar los precios de ese pedido sin afectar a los demÃ¡s.

Activa Prioridad alta solo cuando corresponda. Los horarios son opcionales:
usa Desde si el cliente llega tarde a su casa, Hasta si necesita recibir antes de
cierta hora, o ambos para una franja. Organizar reparto usa esos datos para ordenar las entregas.

## Resumen y entregas

La venta muestra las cantidades totales para preparar, las pendientes de entrega,
los pedidos entregados y el total vendido. Marca Entregado cuando corresponda;
puedes desmarcarlo si hubo un error. Esto no registra un pago.

El lÃ¡piz de cada pedido permite cambiar cantidades, precio, prioridad, horario y
observaciones. El lÃ¡piz superior edita la venta. Los precios generales nuevos
solo se usarÃ¡n en pedidos nuevos; los existentes conservan sus precios.

## Cobros

Abre Ventas, elige la venta por fecha y, en el pedido del cliente, toca Ver cobros.
Registrar abono permite ingresar un importe
parcial, fecha del cobro, efectivo/transferencia/otro y observaciones opcionales.
Pagar saldo completo guarda el saldo que muestra este telÃ©fono. Si el saldo de
Supabase cambiÃ³ mientras no habÃ­a conexiÃ³n, el cobro queda para revisiÃ³n al
sincronizar. El estado cambia
automÃ¡ticamente entre Pendiente, Abono y Pagado.

El historial muestra cada cobro. Si registraste uno por error, usa su papelera y
confirma la eliminaciÃ³n; el saldo se recalcula. No se pueden registrar importes
mayores al saldo ni reducir el total del pedido por debajo de lo ya cobrado.

Para cobrar una deuda de una fecha anterior, abre esa venta y el pedido del
cliente. La fecha del cobro se guarda por separado y el dinero sigue asociado a
la venta original. El resumen de cada venta reÃºne sus cobros y saldos pendientes.

## Gastos y resultado

Dentro de la venta, toca Ver gastos y Nuevo gasto. Solo el importe es obligatorio;
puedes describir quÃ© compraste y elegir la fecha de la compra. Toca un gasto para
editarlo o usa su papelera para eliminar un registro errÃ³neo.

El resumen muestra vendido, cobrado, pendiente y gastos. Resultado significa
vendido menos gastos; Cobrado menos gastos muestra por separado cuÃ¡nto se ha
recibido descontando los gastos registrados. Ambos pueden ser negativos.

## ConexiÃ³n

Abre la actualizaciÃ³n una vez con internet y espera a que la barra superior diga
Sincronizado. DespuÃ©s puedes desconectarte: clientes, pedidos, cobros, gastos y
entregas se guardan en este telÃ©fono y sobreviven a cerrar y volver a abrir la app.

La barra muestra cuÃ¡ntos cambios faltan por enviar. Al recuperar internet,
mantÃ©n la app abierta para sincronizar; tambiÃ©n puedes tocar la barra, actualizar
con la flecha o deslizar hacia abajo. Al volver a abrirla se intenta de nuevo.

Un cobro sin conexiÃ³n aparece como pendiente de sincronizar. Si otro telÃ©fono
cambiÃ³ el saldo o el mismo registro, se conserva el cambio local para revisiÃ³n.
Toca el aviso, revisa el motivo y reintenta o descarta ese cambio local para usar
la versiÃ³n del servidor. Mientras haya un conflicto, los cambios posteriores
esperan. Los datos locales todavÃ­a no enviados solo existen en ese telÃ©fono.

Las rutas y notificaciones se incorporarÃ¡n en siguientes versiones.


### Importar contactos del teléfono

En Clientes, pulsa Importar contactos y permite leer la agenda. Busca y marca uno o varios números, revisa la selección y confirma Importar. Solo se guardan los seleccionados, con nombre y teléfono; luego puedes agregar dirección y ubicación. Los números repetidos o que ya son clientes se omiten. Los números locales de Ecuador se convierten a +593; para otros países guarda el código internacional en la agenda. La importación también se guarda sin internet y se sincroniza al recuperar conexión. No modifica la agenda del teléfono. Los contactos guardados únicamente dentro de WhatsApp deben guardarse primero en la agenda.
