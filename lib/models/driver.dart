class Driver {
  /// Backend user UUID (users.id) — used for trips/history/ownership.
  final String? id;
  /// Human driver code shown in UI (e.g. DRV-204).
  final String driverId;
  final String vehicleNo;
  final String? name;
  final String? phone;
  final String? vehicleType;
  final String? organization;
  final String? approvalStatus;
  /// OFFLINE | AVAILABLE | BUSY — backend-owned, mirrored for display only.
  final String? availability;
  /// Bearer token for authenticated calls. Never trusted for authorization.
  final String? token;

  Driver({
    this.id,
    required this.driverId,
    required this.vehicleNo,
    this.name,
    this.phone,
    this.vehicleType,
    this.organization,
    this.approvalStatus,
    this.availability,
    this.token,
  });

  /// UUID for backend ownership checks, falls back to human code for legacy rows.
  String get backendId => (id != null && id!.isNotEmpty) ? id! : driverId;

  bool get hasToken => token != null && token!.isNotEmpty;

  bool get isApproved => approvalStatus == 'approved';

  /// Display name for the header; falls back to the driver code.
  String get displayName => (name != null && name!.isNotEmpty) ? name! : driverId;

  Driver copyWith({
    String? id,
    String? driverId,
    String? vehicleNo,
    String? name,
    String? phone,
    String? vehicleType,
    String? organization,
    String? approvalStatus,
    String? availability,
    String? token,
    bool clearToken = false,
  }) {
    return Driver(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      vehicleType: vehicleType ?? this.vehicleType,
      organization: organization ?? this.organization,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      availability: availability ?? this.availability,
      token: clearToken ? null : (token ?? this.token),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'vehicleNo': vehicleNo,
      'name': name,
      'phone': phone,
      'vehicleType': vehicleType,
      'organization': organization,
      'approvalStatus': approvalStatus,
      'availability': availability,
      'token': token,
    };
  }

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: (json['id'] ?? json['user_id'])?.toString(),
      driverId: (json['driverId'] ?? json['driver_id'] ?? '').toString(),
      vehicleNo: (json['vehicleNo'] ?? json['vehicle_no'] ?? '').toString(),
      name: json['name']?.toString(),
      phone: json['phone']?.toString(),
      vehicleType: (json['vehicleType'] ?? json['vehicle_type'])?.toString(),
      organization: json['organization']?.toString(),
      approvalStatus: (json['approvalStatus'] ?? json['approval_status'])?.toString(),
      availability: (json['availability'] ?? json['availability_status'])?.toString(),
      token: json['token']?.toString(),
    );
  }
}
