import 'package:app_tamales/data/delivery.dart';
import 'package:app_tamales/data/sales_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

RecordData stop(
  String id,
  double longitude, {
  bool priority = false,
  String? from,
  String? until,
  bool delivered = false,
}) => {
  'id': id,
  'latitude': 0.0,
  'longitude': longitude,
  'high_priority': priority,
  'available_from': from,
  'available_until': until,
  'delivered': delivered,
};
void main() {
  const origin = LatLng(0, 0);
  test(
    'Coordinates validate ranges and reject short links and viewport locations',
    () {
      expect(parseLocation('-2.17, -79.92'), const LatLng(-2.17, -79.92));
      expect(
        parseLocation(
          'https://www.google.com/maps/search/?api=1&query=-2.17%2C-79.92',
        ),
        const LatLng(-2.17, -79.92),
      );
      expect(parseLocation('91, 0'), isNull);
      expect(parseLocation('https://maps.app.goo.gl/opaqueId'), isNull);
      expect(
        parseLocation('https://google.com/maps/@-2.17,-79.92,15z'),
        isNull,
      );
      expect(coordinates({'latitude': double.nan, 'longitude': 0}), isNull);
    },
  );
  test(
    'Available high priority before flexible; delayed priority does not block other clients',
    () {
      final plan = planDelivery(
        [
          stop('near', .001),
          stop('high', .01, priority: true),
          stop('late', .002, priority: true, from: '20:00'),
        ],
        origin,
        12 * 60,
        3,
      );
      expect(plan.visits.map((v) => v.order['id']), ['high', 'near', 'late']);
      expect(plan.visits.last.arrival, 20 * 60);
      expect(plan.visits.last.wait, greaterThan(0));
    },
  );
  test(
    'Missing coordinates are explicit and delivered orders are never routed',
    () {
      final plan = planDelivery(
        [
          stop('done', .01, delivered: true),
          {'id': 'no-pin'},
          stop('pending', .02),
        ],
        origin,
        700,
        3,
      );
      expect(plan.visits.single.order['id'], 'pending');
      expect(plan.missing.single['id'], 'no-pin');
    },
  );
  test(
    'Road matrices use asymmetric direction and include waiting and service duration',
    () {
      final plan = planDelivery(
        [stop('a', .01, from: '12:10'), stop('b', .02)],
        origin,
        720,
        3,
        manualOrder: ['a', 'b'],
        durations: [
          [0, 120, 60],
          [360, 0, 600],
          [60, 60, 0],
        ],
        distances: [
          [0, 1000, 2000],
          [3000, 0, 7000],
          [1000, 2000, 0],
        ],
      );
      expect(plan.visits.first.arrival, 730);
      expect(plan.visits.first.wait, 8);
      expect(plan.visits.last.arrival, 743);
      expect(plan.finish, 746);
      expect(plan.distance, 8);
    },
  );
  test(
    'Manual postpone overrides priority and warns about missed time window',
    () {
      final plan = planDelivery(
        [
          stop('priority', .01, priority: true, until: '12:00'),
          stop('flex', .02),
        ],
        origin,
        720,
        3,
        manualOrder: ['flex', 'priority'],
      );
      expect(plan.visits.first.order['id'], 'flex');
      expect(plan.visits.last.late, greaterThan(0));
    },
  );
  test('Forty orders are visited once, with day rollover visible', () {
    final orders = List.generate(40, (i) => stop('$i', i / 1000));
    final plan = planDelivery(orders, origin, 23 * 60, 3);
    expect(plan.visits.length, 40);
    expect(plan.visits.map((v) => v.order['id']).toSet().length, 40);
    expect(clockLabel(plan.finish), contains('(+1 día)'));
  });
}
