import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_store.dart';
import 'sales_repository.dart';

class RoadMatrix {
  RoadMatrix(this.durations, this.distances);
  final List<List<double?>> durations, distances;
  factory RoadMatrix.fromJson(Map data) {
    List<List<double?>> matrix(Object? raw) => (raw as List)
        .map(
          (r) => (r as List)
              .map((n) => n == null ? null : (n as num).toDouble())
              .toList(),
        )
        .toList();
    return RoadMatrix(matrix(data['durations']), matrix(data['distances']));
  }
  static Future<RoadMatrix> load(
    LocalStore store,
    List<LatLng> points, {
    bool allowNetwork = true,
  }) async {
    if (points.length > 59) {
      throw DataValidationException(
        'El cálculo por calles admite hasta 58 entregas por recorrido. Selecciona un grupo menor.',
      );
    }
    final locations = points.map((p) => [p.longitude, p.latitude]).toList();
    final fingerprint = jsonEncode(locations);
    final cached = await store.meta('road_matrix');
    if (cached != null) {
      final data = jsonDecode(cached) as Map;
      final recent =
          DateTime.now()
              .difference(DateTime.parse(data['at'] as String))
              .inHours <
          12;
      final oldPoints = jsonDecode(data['points'] as String) as List;
      final indices = locations
          .map((p) => oldPoints.indexWhere((o) => o[0] == p[0] && o[1] == p[1]))
          .toList();
      if (recent && indices.every((i) => i >= 0)) {
        final full = RoadMatrix.fromJson(data['matrix'] as Map);
        return RoadMatrix(
          indices
              .map((i) => indices.map((j) => full.durations[i][j]).toList())
              .toList(),
          indices
              .map((i) => indices.map((j) => full.distances[i][j]).toList())
              .toList(),
        );
      }
    }

    if (!allowNetwork) {
      throw DataValidationException(
        'Pulsa Calcular para actualizar los tiempos por calles o desactiva esa opción para estimar sin internet.',
      );
    }
    try {
      final result = await Supabase.instance.client.functions
          .invoke('delivery-matrix', body: {'locations': locations})
          .timeout(const Duration(seconds: 35));
      final raw = result.data as Map;
      final matrix = RoadMatrix.fromJson(raw);
      if (matrix.durations.length != points.length ||
          matrix.distances.length != points.length ||
          matrix.durations.any(
            (r) =>
                r.length != points.length || r.any((v) => v == null || v < 0),
          ) ||
          matrix.distances.any(
            (r) =>
                r.length != points.length || r.any((v) => v == null || v < 0),
          )) {
        throw DataValidationException(
          'No hay conexión por carretera entre algunos puntos. Revisa las ubicaciones o usa el cálculo aproximado.',
        );
      }
      await store.setMeta(
        'road_matrix',
        jsonEncode({
          'points': fingerprint,
          'at': DateTime.now().toIso8601String(),
          'matrix': raw,
        }),
      );
      return matrix;
    } on DataValidationException {
      rethrow;
    } catch (_) {
      throw DataValidationException(
        'No se pudo calcular por calles. Revisa internet o vuelve a intentarlo más tarde. Puedes desactivar esa opción para ordenar por cercanía sin internet.',
      );
    }
  }
}
