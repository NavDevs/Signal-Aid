import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/driver.dart';
import '../models/trip.dart';

class TripsProvider with ChangeNotifier {
  static const String _tripsKey = '@signalaid:trips:v1';
  static const String _driverKey = '@signalaid:driver:v1';

  List<Trip> _trips = [];
  Driver? _driver;
  bool _loading = true;

  List<Trip> get trips => _trips;
  Driver? get driver => _driver;
  bool get loading => _loading;

  TripsProvider() {
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tripsJson = prefs.getString(_tripsKey);
      final driverJson = prefs.getString(_driverKey);

      if (tripsJson != null) {
        final List<dynamic> decoded = json.decode(tripsJson);
        _trips = decoded.map((e) => Trip.fromJson(e)).toList();
      } else {
        _trips = _seedTrips();
        await prefs.setString(_tripsKey, json.encode(_trips.map((e) => e.toJson()).toList()));
      }

      if (driverJson != null) {
        _driver = Driver.fromJson(json.decode(driverJson));
      }
    } catch (e) {
      _trips = _seedTrips();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<Trip> _seedTrips() {
    return [
      Trip(
        id: 'seed-1',
        date: '2026-04-19',
        time: '14:30',
        travelTime: 71.2,
        preemptions: 3,
        confidence: 98,
        distance: 5.2,
        criticality: Criticality.high,
        driverId: 'DRV-204',
        vehicleNo: 'AMB-1187',
      ),
      Trip(
        id: 'seed-2',
        date: '2026-04-18',
        time: '09:15',
        travelTime: 68.5,
        preemptions: 2,
        confidence: 97,
        distance: 4.8,
        criticality: Criticality.critical,
        driverId: 'DRV-204',
        vehicleNo: 'AMB-1187',
      ),
      Trip(
        id: 'seed-3',
        date: '2026-04-17',
        time: '18:45',
        travelTime: 75.0,
        preemptions: 4,
        confidence: 96,
        distance: 5.5,
        criticality: Criticality.high,
        driverId: 'DRV-204',
        vehicleNo: 'AMB-1187',
      ),
    ];
  }

  Future<void> setDriver(Driver? driver) async {
    _driver = driver;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    if (driver != null) {
      await prefs.setString(_driverKey, json.encode(driver.toJson()));
    } else {
      await prefs.remove(_driverKey);
    }
  }

  Future<Trip> addTrip({
    required double travelTime,
    required int preemptions,
    required int confidence,
    required double distance,
    required Criticality criticality,
    required String driverId,
    required String vehicleNo,
  }) async {
    final now = DateTime.now();
    final trip = Trip(
      id: '${now.millisecondsSinceEpoch}${now.microsecond}',
      date: now.toIso8601String().split('T')[0],
      time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      travelTime: travelTime,
      preemptions: preemptions,
      confidence: confidence,
      distance: distance,
      criticality: criticality,
      driverId: driverId,
      vehicleNo: vehicleNo,
    );

    _trips = [trip, ..._trips];
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tripsKey, json.encode(_trips.map((e) => e.toJson()).toList()));

    return trip;
  }
}
