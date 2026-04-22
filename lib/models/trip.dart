enum Criticality { normal, high, critical }

class Trip {
  final String id;
  final String date;
  final String time;
  final double travelTime;
  final int preemptions;
  final int confidence;
  final double distance;
  final Criticality criticality;
  final String driverId;
  final String vehicleNo;

  Trip({
    required this.id,
    required this.date,
    required this.time,
    required this.travelTime,
    required this.preemptions,
    required this.confidence,
    required this.distance,
    required this.criticality,
    required this.driverId,
    required this.vehicleNo,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'time': time,
      'travelTime': travelTime,
      'preemptions': preemptions,
      'confidence': confidence,
      'distance': distance,
      'criticality': criticality.name,
      'driverId': driverId,
      'vehicleNo': vehicleNo,
    };
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'],
      date: json['date'],
      time: json['time'],
      travelTime: json['travelTime'],
      preemptions: json['preemptions'],
      confidence: json['confidence'],
      distance: json['distance'],
      criticality: Criticality.values.firstWhere(
        (e) => e.name == json['criticality'],
        orElse: () => Criticality.high,
      ),
      driverId: json['driverId'],
      vehicleNo: json['vehicleNo'],
    );
  }
}
