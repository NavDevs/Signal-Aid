import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages a Supabase Realtime channel that listens for new road_report rows
/// inserted by Roadly users.
///
/// Usage:
///   final rt = RealtimeService();
///   rt.subscribeToIncidents((payload) { /* handle new incident */ });
///   // later:
///   rt.dispose();
class RealtimeService {
  RealtimeChannel? _channel;

  SupabaseClient get _client => Supabase.instance.client;

  /// Subscribes to INSERT events on the `road_reports` table.
  /// [onNew] is called with the new row's data whenever a new report arrives.
  ///
  /// Safe to call multiple times — disposes the old channel first.
  void subscribeToIncidents(Function(Map<String, dynamic>) onNew) {
    // Clean up any existing subscription before creating a new one.
    dispose();

    try {
      _channel = _client
          .channel('public:road_reports')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'road_reports',
            callback: (payload) {
              try {
                final newRow = payload.newRecord;
                if (newRow.isNotEmpty) {
                  onNew(newRow);
                }
              } catch (e) {
                debugPrint('RealtimeService: error handling new incident: $e');
              }
            },
          )
          .subscribe((status, [error]) {
            debugPrint('RealtimeService: channel status = $status');
            if (error != null) {
              debugPrint('RealtimeService: subscription error: $error');
            }
          });
    } catch (e) {
      debugPrint('RealtimeService.subscribeToIncidents error: $e');
    }
  }

  /// Unsubscribes and removes the Realtime channel. Call this in dispose().
  void dispose() {
    try {
      if (_channel != null) {
        _client.removeChannel(_channel!);
        _channel = null;
      }
    } catch (e) {
      debugPrint('RealtimeService.dispose error: $e');
    }
  }
}
