class Driver {
  final String driverId;
  final String vehicleNo;

  Driver({
    required this.driverId,
    required this.vehicleNo,
  });

  Map<String, dynamic> toJson() {
    return {
      'driverId': driverId,
      'vehicleNo': vehicleNo,
    };
  }

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      driverId: json['driverId'],
      vehicleNo: json['vehicleNo'],
    );
  }
}
