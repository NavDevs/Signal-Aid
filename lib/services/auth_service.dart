import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps all Supabase Auth calls for Signal-Aid drivers.
///
/// Auth strategy (MVP):
///   email    = "<driverId>@signalaid.local"
///   password = vehicleNo
///
/// This is a simple scheme that lets drivers "log in" without a real email.
/// In production you would replace this with a proper auth flow.
class AuthService {
  // Convenient accessor for the Supabase client singleton.
  SupabaseClient get _client => Supabase.instance.client;

  /// Returns true when a valid Supabase session exists.
  bool get isSignedIn => _client.auth.currentSession != null;

  /// Returns the Supabase user-id (UUID) of the currently signed-in user,
  /// or null when not signed in.
  String? get userId => _client.auth.currentUser?.id;

  /// Signs the driver in (or creates their account on first use) using:
  ///   email    = "<driverId>@signalaid.local"
  ///   password = vehicleNo
  ///
  /// After a successful sign-in the driver's profile row in the `profiles`
  /// table is upserted so other parts of the system can look up their details.
  Future<void> signInAsDriver({
    required String driverId,
    required String vehicleNo,
  }) async {
    final email = '${driverId.toLowerCase()}@signalaid.local';

    try {
      // Try sign-in first.
      await _client.auth.signInWithPassword(
        email: email,
        password: vehicleNo,
      );
    } on AuthException catch (e) {
      // "Invalid login credentials" → the account does not exist yet; create it.
      if (e.statusCode == '400' || e.message.contains('Invalid login')) {
        await _client.auth.signUp(
          email: email,
          password: vehicleNo,
        );
        // Sign in immediately after account creation.
        await _client.auth.signInWithPassword(
          email: email,
          password: vehicleNo,
        );
      } else {
        rethrow;
      }
    }

    // Upsert a profile row so the shared `profiles` table stays in sync.
    final uid = _client.auth.currentUser?.id;
    if (uid != null) {
      try {
        await _client.from('profiles').upsert({
          'id': uid,
          'role': 'emergency_driver',
          'driver_id': driverId,
          'vehicle_no': vehicleNo,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (profileError) {
        // Non-fatal — the app still works even if the profile row fails.
        debugPrint('AuthService: profile upsert failed: $profileError');
      }
    }
  }

  /// Signs the current driver out.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('AuthService: signOut error: $e');
    }
  }
}
