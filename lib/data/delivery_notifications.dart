import 'package:flutter/services.dart';

/// Android owns the notification, so it stays visible with Flutter backgrounded.
/// No foreground service, polling or background location is necessary.
class DeliveryNotifications {
  static const _channel = MethodChannel('tamales/delivery');
  static Future<bool> show({
    required String saleId,
    required String title,
    required String body,
    required String destination,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('show', {
            'saleId': saleId,
            'title': title,
            'body': body,
            'destination': destination,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      /* Tests and non-Android. */
    }
  }

  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('notificationSettings');
    } on MissingPluginException {
      /* Android only. */
    }
  }

  static Future<String?> pendingSale() async {
    try {
      return await _channel.invokeMethod<String>('pendingSale');
    } on MissingPluginException {
      return null;
    }
  }

  static void listen(Future<void> Function(String) open) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSale' && call.arguments is String) {
        await open(call.arguments as String);
      }
    });
  }
}
