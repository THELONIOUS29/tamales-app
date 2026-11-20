import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'sales_repository.dart';

LatLng? coordinates(Map data) {
  final lat = data['latitude'], lon = data['longitude'];
  if (lat is! num ||
      lon is! num ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 90 ||
      lon.abs() > 180) {
    return null;
  }
  return LatLng(lat.toDouble(), lon.toDouble());
}

/// Accept coordinates and expanded map links, never infer a position from a
/// short link's opaque ID or a map's viewport (@lat,lon).
LatLng? parseLocation(String text) {
  final uri = Uri.tryParse(text.trim());
  final candidate =
      uri?.queryParameters['query'] ?? uri?.queryParameters['q'] ?? text.trim();
  final match = RegExp(
    r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
  ).firstMatch(candidate);
  if (match == null) return null;
  return coordinates({
    'latitude': double.tryParse(match[1]!),
    'longitude': double.tryParse(match[2]!),
  });
}

double kilometers(LatLng a, LatLng b) =>
    const Distance().as(LengthUnit.Kilometer, a, b);
int? clockMinutes(Object? value) {
  if (value == null) return null;
  final parts = value.toString().split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String clockLabel(int minute) {
  final day = minute ~/ 1440;
  final m = minute % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}${day > 0 ? ' (+$day día)' : ''}';
}

class DeliveryVisit {
  const DeliveryVisit(this.order, this.arrival, this.wait, this.late, this.km);
  final RecordData order;
  final int arrival, wait, late;
  final double km;
}

class DeliveryPlan {
  const DeliveryPlan(this.visits, this.missing, this.finish, this.distance);
  final List<DeliveryVisit> visits;
  final List<RecordData> missing;
  final int finish;
  final double distance;
}

/// A small deterministic planner. High priority is served before flexible
/// deliveries when available; late-opening priority clients do not force the
/// driver to wait while other clients can be served. This is an estimate, not
/// a road/traffic model or a guarantee of a globally optimal tour.
DeliveryPlan planDelivery(
  List<RecordData> orders,
  LatLng origin,
  int start,
  int serviceMinutes, {
  List<String>? manualOrder,
  List<List<double?>>? durations,
  List<List<double?>>? distances,
  bool optimize = true,
}) {
  final pending = orders.where((o) => o['delivered'] != true).toList();
  final missing = pending.where((o) => coordinates(o) == null).toList();
  final remaining = pending.where((o) => coordinates(o) != null).toList();
  final original = [...remaining];
  final visits = <DeliveryVisit>[];
  var point = origin, time = start, sourceIndex = 0;
  var totalKm = 0.0;
  while (remaining.isNotEmpty) {
    double km(RecordData o) {
      final index = original.indexOf(o) + 1;
      return distances?[sourceIndex][index] != null
          ? distances![sourceIndex][index]! / 1000
          : kilometers(point, coordinates(o)!);
    }

    int travel(RecordData o) {
      final index = original.indexOf(o) + 1;
      return durations?[sourceIndex][index] != null
          ? (durations![sourceIndex][index]! / 60).ceil()
          : math.max(1, (km(o) * 1.35 / 25 * 60).ceil());
    }

    final ready = remaining
        .where(
          (o) => (clockMinutes(o['available_from']) ?? 0) <= time + travel(o),
        )
        .toList();
    final priority = ready.where((o) => o['high_priority'] == true).toList();
    final candidates = manualOrder != null
        ? [...remaining]
        : priority.isNotEmpty
        ? priority
        : ready.isNotEmpty
        ? ready
        : [...remaining];
    candidates.sort((a, b) {
      if (manualOrder != null) {
        final ai = manualOrder.indexOf(a['id'] as String);
        final bi = manualOrder.indexOf(b['id'] as String);
        return (ai < 0 ? 100000 : ai).compareTo(bi < 0 ? 100000 : bi);
      }
      double score(RecordData o) {
        final arrival = math.max(
          time + travel(o),
          clockMinutes(o['available_from']) ?? 0,
        );
        final deadline = clockMinutes(o['available_until']);
        final late = deadline == null ? 0 : math.max(0, arrival - deadline);
        final urgency = deadline == null
            ? 0
            : math.max(0, 60 - (deadline - arrival));
        return late * 10000 + (arrival - time) - urgency * .8;
      }

      final result = score(a).compareTo(score(b));
      return result != 0
          ? result
          : (a['id'] as String).compareTo(b['id'] as String);
    });
    final next = candidates.first;
    final distance = km(next), reach = time + travel(next);
    final arrival = math.max(reach, clockMinutes(next['available_from']) ?? 0);
    final deadline = clockMinutes(next['available_until']);
    visits.add(
      DeliveryVisit(
        next,
        arrival,
        arrival - reach,
        deadline == null ? 0 : math.max(0, arrival - deadline),
        distance,
      ),
    );
    totalKm += distance;
    time = arrival + serviceMinutes;
    sourceIndex = original.indexOf(next) + 1;
    point = coordinates(next)!;
    remaining.remove(next);
  }
  var best = DeliveryPlan(visits, missing, time, totalKm);
  if (optimize &&
      manualOrder == null &&
      visits.length > 2 &&
      visits.length <= 80) {
    int priorityInversions(DeliveryPlan plan) {
      var count = 0;
      for (var i = 0; i < plan.visits.length; i++) {
        final v = plan.visits[i];
        if (v.order['high_priority'] == true) continue;
        for (final later in plan.visits.skip(i + 1)) {
          if (later.order['high_priority'] == true &&
              (clockMinutes(later.order['available_from']) ?? 0) <= v.arrival) {
            count++;
          }
        }
      }
      return count;
    }

    double score(DeliveryPlan p) =>
        p.visits.fold<int>(0, (n, v) => n + v.late) * 1000000.0 +
        p.finish -
        start +
        p.distance * .01;
    final maxInversions = priorityInversions(best);
    // Bounded local improvement limits CPU use even for a large delivery day.
    for (var pass = 0; pass < 2; pass++) {
      var improved = false;
      for (var i = 0; i < visits.length - 1; i++) {
        for (var j = i + 1; j < math.min(visits.length, i + 9); j++) {
          final ids = best.visits.map((v) => v.order['id'] as String).toList();
          final section = ids.sublist(i, j + 1).reversed.toList();
          ids.replaceRange(i, j + 1, section);
          final candidate = planDelivery(
            orders,
            origin,
            start,
            serviceMinutes,
            manualOrder: ids,
            durations: durations,
            distances: distances,
            optimize: false,
          );
          if (priorityInversions(candidate) <= maxInversions &&
              score(candidate) < score(best)) {
            best = candidate;
            improved = true;
          }
        }
      }
      if (!improved) break;
    }
  }
  return best;
}
