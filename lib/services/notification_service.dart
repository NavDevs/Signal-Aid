import 'dart:convert';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Alarm ID used for the repeating background poll.
// Must be a stable integer — never change it across app versions.
// ---------------------------------------------------------------------------
const int _kAlarmId = 7842;

// ---------------------------------------------------------------------------
// Background callback — top-level, never inside a class.
// AlarmManager wakes the app and calls this even when it is killed.
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _alarmCallback() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final driverId    = prefs.getString('notif_driver_id');
    final vehicleType = prefs.getString('notif_vehicle_type');
    final token       = prefs.getString('notif_token');
    if (driverId == null || vehicleType == null || token == null) return;

    const baseUrl = 'https://clearpath-server.onrender.com';
    final response = await http
        .get(Uri.parse('$baseUrl/api/dispatches'),
            headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return;
    final List<dynamic> dispatches = json.decode(response.body);

    final seenRaw  = prefs.getStringList('notif_seen_ids') ?? [];
    final seen     = seenRaw.toSet();
    final matchTypes = _matchingTypes(vehicleType);

    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android));

    // Create the notification channel (required on Android 8+)
    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationService.channelId,
        NotificationService.channelName,
        description: NotificationService.channelDesc,
        importance: Importance.max,
      ),
    );

    int notifId    = 100;
    final newSeen  = <String>{...seen};

    for (final d in dispatches) {
      final id = d['id']?.toString();
      if (id == null) continue;
      newSeen.add(id);
      if (seen.contains(id)) continue; // already notified

      final type = (d['type'] ?? '').toString().toLowerCase();
      if (!matchTypes.contains(type)) continue;

      final address     = d['address']?.toString() ?? 'Unknown location';
      final description = d['description']?.toString() ?? '';

      await plugin.show(
        notifId++,
        '🚨 ${_prettyType(type)} Emergency',
        '$address${description.isNotEmpty ? ' — $description' : ''}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationService.channelId,
            NotificationService.channelName,
            channelDescription: NotificationService.channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFFEF4444),
            enableVibration: true,
            playSound: true,
            autoCancel: true,
          ),
        ),
      );
    }

    // Persist seen IDs (capped at 200)
    final trimmed = newSeen.toList();
    if (trimmed.length > 200) trimmed.removeRange(0, trimmed.length - 200);
    await prefs.setStringList('notif_seen_ids', trimmed);
  } catch (e) {
    debugPrint('[Notif BG] $e');
  }
}

Set<String> _matchingTypes(String vehicleType) {
  switch (vehicleType.toLowerCase()) {
    case 'fire':      return {'fire'};
    case 'ambulance': return {'accident'};
    case 'police':    return {'accident', 'congestion', 'blocked'};
    default:          return {'fire', 'accident', 'congestion', 'blocked', 'flooding'};
  }
}

String _prettyType(String type) {
  switch (type) {
    case 'fire':       return 'Fire';
    case 'accident':   return 'Accident';
    case 'congestion': return 'Congestion';
    case 'blocked':    return 'Road Blocked';
    case 'flooding':   return 'Flooding';
    default: return type.isNotEmpty ? type[0].toUpperCase() + type.substring(1) : type;
  }
}

// ---------------------------------------------------------------------------
// NotificationService — singleton for in-app use
// ---------------------------------------------------------------------------
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelId   = 'signalaid_emergency';
  static const String channelName = 'Emergency Dispatches';
  static const String channelDesc = 'Alerts for fire and accident emergency dispatches';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Init ────────────────────────────────────────────────────────────────
  /// Call once in main() before runApp.
  Future<void> init() async {
    if (_initialized) return;

    // Initialize AlarmManager
    await AndroidAlarmManager.initialize();

    // Initialize local notifications plugin
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onTap,
    );

    // Create the notification channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDesc,
            importance: Importance.max,
          ),
        );

    // Request Android 13+ notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
    debugPrint('[Notif] Initialized.');
  }

  // ── Start polling ────────────────────────────────────────────────────────
  /// Call after a successful login. Saves credentials and schedules a
  /// repeating alarm that fires every 15 minutes — even when app is killed.
  Future<void> startPolling({
    required String driverId,
    required String vehicleType,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_driver_id', driverId);
    await prefs.setString('notif_vehicle_type', vehicleType);
    await prefs.setString('notif_token', token);
    await prefs.setStringList('notif_seen_ids', []); // fresh start on login

    // Cancel any previous alarm and schedule a new one
    await AndroidAlarmManager.cancel(_kAlarmId);
    await AndroidAlarmManager.periodic(
      const Duration(minutes: 15),
      _kAlarmId,
      _alarmCallback,
      wakeup: true,       // wake the CPU from sleep
      rescheduleOnReboot: true, // survive device restart
      exact: false,       // inexact is fine and uses less battery
    );

    debugPrint('[Notif] Alarm polling started — $vehicleType / $driverId');
  }

  // ── Stop polling ─────────────────────────────────────────────────────────
  /// Call on explicit logout.
  Future<void> stopPolling() async {
    await AndroidAlarmManager.cancel(_kAlarmId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notif_driver_id');
    await prefs.remove('notif_vehicle_type');
    await prefs.remove('notif_token');
    await prefs.remove('notif_seen_ids');
    debugPrint('[Notif] Alarm polling stopped.');
  }

  // ── Foreground notification ───────────────────────────────────────────────
  /// Called from Socket.IO handler while app is open — instant heads-up.
  Future<void> showDispatchNotification(Map<String, dynamic> dispatch) async {
    if (!_initialized) return;
    final type        = (dispatch['type'] ?? '').toString().toLowerCase();
    final address     = dispatch['address']?.toString() ?? 'Unknown location';
    final description = dispatch['description']?.toString() ?? '';
    final id          = dispatch['id']?.toString() ?? '0';

    await _plugin.show(
      id.hashCode.abs() % 1000,
      '🚨 ${_prettyType(type)} Emergency',
      '$address${description.isNotEmpty ? ' — $description' : ''}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFFEF4444),
          enableVibration: true,
          playSound: true,
          autoCancel: true,
          fullScreenIntent: true,
        ),
      ),
    );
  }

  void _onTap(NotificationResponse details) {
    debugPrint('[Notif] Tapped: ${details.payload}');
  }
}
