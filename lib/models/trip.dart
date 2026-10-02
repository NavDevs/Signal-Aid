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
  final String? reportId;

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
    this.reportId,
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
      if (reportId != null) 'reportId': reportId,
    };
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: '${json['id'] ?? ''}',
      date: '${json['date'] ?? ''}',
      time: '${json['time'] ?? ''}',
      travelTime: (json['travelTime'] as num?)?.toDouble() ?? 0.0,
      preemptions: (json['preemptions'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toInt() ?? 0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      criticality: Criticality.values.firstWhere(
        (e) => e.name == json['criticality'],
        orElse: () => Criticality.high,
      ),
      driverId: '${json['driverId'] ?? json['driver_id'] ?? ''}',
      vehicleNo: '${json['vehicleNo'] ?? json['vehicle_no'] ?? ''}',
      reportId: (json['reportId'] ?? json['report_id'])?.toString(),
    );
  }
}
