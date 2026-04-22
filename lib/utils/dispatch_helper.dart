import '../models/intersection.dart';
import '../models/trip.dart';

class DispatchHelper {
  static const List<Map<String, dynamic>> _corridor = [
    {'id': 'I1', 'name': 'Linden & 4th', 'distanceKm': 0.6},
    {'id': 'I2', 'name': 'Market Crossing', 'distanceKm': 1.4},
    {'id': 'I3', 'name': 'Harbor Bridge', 'distanceKm': 2.3},
    {'id': 'I4', 'name': 'Mercy Hospital Gate', 'distanceKm': 3.1},
    {'id': 'I5', 'name': 'Oak Boulevard', 'distanceKm': 4.0},
  ];

  static DispatchPlan computeDispatchPlan(Criticality criticality) {
    final profile = {
      Criticality.normal: {'eta': 92, 'speed': 42, 'preemptCount': 2, 'conf': 94, 'distance': 4.6},
      Criticality.high: {'eta': 71, 'speed': 50, 'preemptCount': 3, 'conf': 97, 'distance': 5.0},
      Criticality.critical: {'eta': 58, 'speed': 58, 'preemptCount': 5, 'conf': 99, 'distance': 5.4},
    }[criticality]!;

    final preemptions = _corridor
        .take(profile['preemptCount'] as int)
        .map((i) => Intersection(
              id: i['id'],
              name: i['name'],
              distanceKm: i['distanceKm'],
              status: IntersectionStatus.preempted,
            ))
        .toList();

    return DispatchPlan(
      eta: profile['eta'] as int,
      distance: profile['distance'] as double,
      speed: profile['speed'] as int,
      preemptions: preemptions,
      confidence: profile['conf'] as int,
    );
  }
}
