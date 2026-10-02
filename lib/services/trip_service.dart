import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip.dart';

/// Handles reading and writing trip records in the `emergency_trips` table.
///
/// Table columns expected in Supabase:
///   id            TEXT PRIMARY KEY
///   started_at    TIMESTAMPTZ          (mapped to date + time fields locally)
///   travel_time   DOUBLE PRECISION
///   preemptions   INT
///   confidence    INT
///   distance      DOUBLE PRECISION
///   criticality   TEXT                 ('normal' | 'high' | 'critical')
///   driver_id     TEXT
///   vehicle_no    TEXT
///   report_id     TEXT NULLABLE        (foreign key to road_reports.id)
class TripService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Fetches all trips for [userId] ordered newest first.
  /// Returns an empty list on any error so the UI never crashes.
  Future<List<Trip>> fetchTrips(String userId) async {
    try {
      final rows = await _client
          .from('emergency_trips')
          .select()
          .eq('driver_id', userId)
          .order('started_at', ascending: false);

      return (rows as List<dynamic>).map((row) => _rowToTrip(row as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('TripService.fetchTrips error: $e');
      return [];
    }
  }

  /// Inserts a new trip row and returns the mapped [Trip] object.
  /// Falls back to a locally-built [Trip] if the insert fails (offline mode).
  Future<Trip> createTrip({
    required String driverId,
    required String vehicleNo,
    required Criticality criticality,
    required double travelTime,
    required int preemptions,
    required int confidence,
    required double distance,
    String? reportId,
  }) async {
    final now = DateTime.now();
    final localId = '${now.millisecondsSinceEpoch}${now.microsecond}';

    try {
      final row = await _client
          .from('emergency_trips')
          .insert({
            'id': localId,
            'started_at': now.toIso8601String(),
            'travel_time': travelTime,
            'preemptions': preemptions,
            'confidence': confidence,
            'distance': distance,
            'criticality': criticality.name,
            'driver_id': driverId,
            'vehicle_no': vehicleNo,
            if (reportId != null) 'report_id': reportId,
          })
          .select()
          .single();

      return _rowToTrip(row);
    } catch (e) {
      debugPrint('TripService.createTrip error (using local fallback): $e');
      // Return a locally-constructed trip so addTrip() still works offline.
      return Trip(
        id: localId,
        date: now.toIso8601String().split('T')[0],
        time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        travelTime: travelTime,
        preemptions: preemptions,
        confidence: confidence,
        distance: distance,
        criticality: criticality,
        driverId: driverId,
        vehicleNo: vehicleNo,
        reportId: reportId,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Converts a raw Supabase row map into a [Trip] model.
  Trip _rowToTrip(Map<String, dynamic> row) {
    final startedAt = row['started_at'] != null
        ? DateTime.parse(row['started_at'] as String)
        : DateTime.now();

    return Trip(
      id: (row['id'] ?? '').toString(),
      date: startedAt.toIso8601String().split('T')[0],
      time: '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}',
      travelTime: (row['travel_time'] as num?)?.toDouble() ?? 0.0,
      preemptions: (row['preemptions'] as num?)?.toInt() ?? 0,
      confidence: (row['confidence'] as num?)?.toInt() ?? 0,
      distance: (row['distance'] as num?)?.toDouble() ?? 0.0,
      criticality: Criticality.values.firstWhere(
        (e) => e.name == row['criticality'],
        orElse: () => Criticality.high,
      ),
      driverId: (row['driver_id'] ?? '').toString(),
      vehicleNo: (row['vehicle_no'] ?? '').toString(),
      reportId: row['report_id'] as String?,
    );
  }
}
