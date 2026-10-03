import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:signalaid_flutter/models/driver.dart';
import 'package:signalaid_flutter/screens/splash_screen.dart';

void main() {
  testWidgets('S0 splash renders the brand while the session is restored',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('SignalAid'), findsOneWidget);
    expect(find.text('Emergency Response System'), findsOneWidget);
    expect(find.text('Verifying your session…'), findsOneWidget);
  });

  testWidgets('S0 splash tells the driver when it is starting offline',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen(offline: true)));

    expect(find.text('Starting offline…'), findsOneWidget);
  });

  group('Driver session model', () {
    test('round-trips through JSON including the bearer token', () {
      final driver = Driver(
        id: 'uuid-1',
        driverId: 'DRV-204',
        vehicleNo: 'AMB-1187',
        name: 'Ravi Kumar',
        phone: '9876543210',
        vehicleType: 'ambulance',
        organization: 'City Hospital',
        approvalStatus: 'approved',
        
        token: 'jwt-token',
      );

      final restored = Driver.fromJson(driver.toJson());

      expect(restored.id, 'uuid-1');
      expect(restored.driverId, 'DRV-204');
      expect(restored.vehicleNo, 'AMB-1187');
      expect(restored.approvalStatus, 'approved');
      expect(restored.hasToken, isTrue);
    });

    test('reads the backend snake_case column names', () {
      final restored = Driver.fromJson({
        'id': 'uuid-2',
        'driver_id': 'FIRE-01',
        'vehicle_no': 'FIRE-1001',
        'vehicle_type': 'fire',
        'approval_status': 'pending',
      });

      expect(restored.driverId, 'FIRE-01');
      expect(restored.vehicleNo, 'FIRE-1001');
      expect(restored.vehicleType, 'fire');
      expect(restored.isApproved, isFalse);
      expect(restored.hasToken, isFalse);
    });

    test('falls back to the human driver code when no UUID is present', () {
      final legacy = Driver(driverId: 'DRV-900', vehicleNo: 'AMB-900');
      expect(legacy.backendId, 'DRV-900');
      expect(legacy.displayName, 'DRV-900');
    });

    test('copyWith can drop a refused token while keeping identity', () {
      final driver = Driver(
        driverId: 'DRV-204',
        vehicleNo: 'AMB-1187',
        token: 'stale-token',
      );

      final cleared = driver.copyWith(clearToken: true, approvalStatus: 'rejected');

      expect(cleared.hasToken, isFalse);
      expect(cleared.driverId, 'DRV-204');
      expect(cleared.approvalStatus, 'rejected');
    });
  });
}
