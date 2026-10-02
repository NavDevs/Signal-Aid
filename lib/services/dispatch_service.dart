import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches incident reports created by Roadly users from the shared
/// `road_reports` table.
///
/// Signal-Aid drivers use this to see pending/verified incidents so they can
/// respond to them from the dispatch screen.
///
/// Expected `road_reports` columns:
///   id          UUID / TEXT
///   status      TEXT   ('pending' | 'verified' | 'resolved' | ...)
///   description TEXT NULLABLE
///   latitude    DOUBLE PRECISION NULLABLE
///   longitude   DOUBLE PRECISION NULLABLE
///   created_at  TIMESTAMPTZ
class DispatchService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Returns up to 20 road reports with status 'pending' or 'verified',
  /// newest first. Returns an empty list on error (offline or permissions).
  Future<List<Map<String, dynamic>>> fetchPendingIncidents() async {
    try {
      final rows = await _client
          .from('road_reports')
          .select('id, status, description, latitude, longitude, created_at')
          .or('status.eq.pending,status.eq.verified')
          .order('created_at', ascending: false)
          .limit(20);

      return (rows as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('DispatchService.fetchPendingIncidents error: $e');
      return [];
    }
  }
}
