enum IntersectionStatus { preempted, queued, passed }

class Intersection {
  final String id;
  final String name;
  final double distanceKm;
  final IntersectionStatus status;

  Intersection({
    required this.id,
    required this.name,
    required this.distanceKm,
    required this.status,
  });
}

class DispatchPlan {
  final int eta;
  final double distance;
  final int speed;
  final List<Intersection> preemptions;
  final int confidence;

  DispatchPlan({
    required this.eta,
    required this.distance,
    required this.speed,
    required this.preemptions,
    required this.confidence,
  });
}
