import 'package:flutter/services.dart';

/// Local Ecuador numbers use +593; other countries must include their prefix.
String? contactPhone(String raw) {
  var value = raw.trim().replaceAll(RegExp(r'[\s().-]'), '');
  if (value.startsWith('00')) value = '+${value.substring(2)}';
  if (RegExp(r'^0[2-7]\d{7}$|^09\d{8}$').hasMatch(value)) {
    value = '+593${value.substring(1)}';
  } else if (RegExp(r'^593\d{8,9}$').hasMatch(value)) {
    value = '+$value';
  }
  return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(value) ? value : null;
}

class PhoneContact {
  PhoneContact(this.name, this.phone);
  final String name;
  final String phone;
  bool matches(String search) {
    final query = search.trim().toLowerCase();
    if (name.toLowerCase().contains(query) || phone.contains(query)) {
      return true;
    }
    final digits = query.replaceAll(RegExp(r'[\s().+-]'), '');
    if (!RegExp(r'^\d+$').hasMatch(digits)) return false;
    final local = phone.startsWith('+593') ? '0${phone.substring(4)}' : phone;
    return phone.contains(digits) || local.contains(digits);
  }
}

class PhoneContacts {
  static const channel = MethodChannel('tamales/contacts');
  static Future<List<PhoneContact>> read() async {
    final rows = await channel.invokeListMethod<dynamic>('read') ?? [];
    final unique = <String, PhoneContact>{};
    for (final row in rows) {
      final phone = contactPhone(row['phone'] as String? ?? '');
      if (phone == null) continue;
      final name = (row['name'] as String? ?? '').trim();
      unique.putIfAbsent(
        phone,
        () => PhoneContact(name.isEmpty ? phone : name, phone),
      );
    }
    return unique.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
