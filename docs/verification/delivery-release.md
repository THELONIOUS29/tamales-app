# Verificación de entrega Android 1.0.0+6

- Flutter analyze: sin incidencias (build/analyze-release.log).
- Flutter test: 26 pruebas aprobadas (build/test-all.log).
- APK release arm64 instalado mediante adb install -r en HONOR DNP_NX9, serial A3SQUT5825001662. versionCode 2006; versionName 1.0.0.
- APK: 21.123.483 bytes. SHA256 B01DC686C390199F34DF7EA6914A8AEB2B8381574A302BFBD399CFD32A1621F2.
- Endpoint de calles desplegado: respuesta 403 sin dispositivo autorizado; respuesta correcta de matriz asimétrica para tres puntos públicos tras autorizar una identidad temporal. Identidad eliminada al terminar.
- En teléfono: calcular por calles, prioridad A antes de B, 3.0 km calculados, notificación A con cantidades/saldo; Entregado cambia aviso a B y mantiene saldo; cierre forzado y reapertura restauran reparto; última entrega completa la ruta y retira notificación.
- Mapa verificado visualmente en el APK final: mosaicos, marcador y atribución permanente visibles; formulario de prueba descartado sin guardar.
- Fixtures de clientes/pedidos/venta retirados con delivery_cleanup.sql. La eliminación se descargó al teléfono; solo permanece la venta real del 23/10/2026.
- No se realizaron llamadas ni se enviaron mensajes. No se modificaron ventas/clientes reales durante QA.
- La aplicación quedó abierta en Ventas, sin reparto de prueba activo.
