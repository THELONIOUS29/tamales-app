package com.tamales.app_tamales

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private var contactsResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null
    private var pendingSale: String? = null
    private var pendingNotice: Map<*, *>? = null
    private val manager get() = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tamales/contacts").setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    if (contactsResult != null) result.error("busy", "Contactos en uso", null)
                    else if (checkSelfPermission("android.permission.READ_CONTACTS") == PackageManager.PERMISSION_GRANTED) readContacts(result)
                    else {
                        contactsResult = result
                        requestPermissions(arrayOf("android.permission.READ_CONTACTS"), 402)
                    }
                }
                "settings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        pendingSale = intent?.getStringExtra("saleId")
        manager.createNotificationChannel(NotificationChannel("delivery", "Siguiente entrega", NotificationManager.IMPORTANCE_DEFAULT))
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tamales/delivery")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val args = call.arguments as Map<*, *>
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                        pendingNotice = args
                        if (!getPreferences(MODE_PRIVATE).getBoolean("notificationAsked", false)) {
                        getPreferences(MODE_PRIVATE).edit().putBoolean("notificationAsked", true).apply()
                        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 401)
                        }
                        result.success(false)
                    } else { showNotice(args); result.success(true) }
                }
                "cancel" -> { pendingNotice = null; manager.cancel(700); result.success(null) }
                "notificationSettings" -> {
                    startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName))
                    result.success(null)
                }
                "pendingSale" -> { val id = pendingSale; pendingSale = null; result.success(id) }
                else -> result.notImplemented()
            }
        }
    }
    private fun readContacts(result: MethodChannel.Result) {
        Thread {
            try {
                val phone = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
                val rows = mutableListOf<Map<String, String>>()
                contentResolver.query(phone, arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ), null, null, null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        rows.add(mapOf("name" to (cursor.getString(0) ?: ""), "phone" to (cursor.getString(1) ?: "")))
                    }
                }
                runOnUiThread { result.success(rows) }
            } catch (_: Exception) {
                runOnUiThread { result.error("read_failed", "No se pudieron leer los contactos", null) }
            }
        }.start()
    }
    private fun showNotice(args: Map<*, *>) {
        val open = Intent(this, MainActivity::class.java).putExtra("saleId", args["saleId"] as String)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tap = PendingIntent.getActivity(this, 700, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val nav = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/maps/dir/?api=1&travelmode=driving&destination=" + Uri.encode(args["destination"] as String)))
        val navigation = PendingIntent.getActivity(this, 701, nav, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val body = args["body"] as String
        val notification = Notification.Builder(this, "delivery")
            .setSmallIcon(com.tamales.app_tamales.R.drawable.ic_delivery)
            .setContentTitle(args["title"] as String).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(tap).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Navegar", navigation).build())
            .setVisibility(Notification.VISIBILITY_PRIVATE).build()
        manager.notify(700, notification)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val id = intent.getStringExtra("saleId") ?: return
        channel?.invokeMethod("openSale", id)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 402) {
            val result = contactsResult
            contactsResult = null
            if (result != null) {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) readContacts(result)
                else result.error("permission_denied", "Permite el acceso a los contactos para importarlos", null)
            }
            return
        }
        if (requestCode == 401 && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            pendingNotice?.let { showNotice(it) }
        }
        pendingNotice = null
    }
}
