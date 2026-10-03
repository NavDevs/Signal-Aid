## v2.6.0 — Notification Reliability + Accept Smoothness

### 1. Background Notification Reliability
- Hardened alarm lifecycle via android_alarm_manager_plus; repeating 15-min poll reliably re-arms after app swipe-kill and device reboot.
- Enabled RebootBroadcastReceiver + LOCKED_BOOT_COMPLETED / QUICKBOOT_POWERON / MY_PACKAGE_REPLACED intents so alarms survive reboots and app updates.
- Added persisted last-run guard (SharedPreferences) to prevent duplicate-fire windows and defensive try-catch across every step of the background callback.
- Unified notification params between foreground showDispatchNotification and the background _alarmCallback: fullScreenIntent, Priority.high, Importance.max, vibration, public visibility, single channel signalaid_emergency.

### 2. Role-Gated + Once-Per-Incident Dedup
- Strict dual-field role gate (identical BG/FG paths): dispatch.required_vehicle matches driver vehicleType AND dispatch.type in {fire} for fire / {accident} for ambulance.
- Per-dispatch-id in-process semaphore serializes the SharedPreferences read-modify-write so concurrent socket + alarm delivery of the same incident cannot double-write the seen set.
- Seen-ID set is stored per driver account: notif_seen_ids_DRIVERID, guarantees the one-time rule even when multiple drivers sign in on the same physical device.

### 3. ACCEPT EMERGENCY UI Freeze Fix
- Two-phase accept in TripsProvider: tryAcceptDispatchHttp (HTTP only, zero side effects) then commitAcceptedDispatchUi (list mutation + notifyListeners).
- Dispatch screen now (a) paints progress button on the same frame of the tap, (b) yields Duration.zero so Flutter draws the spinner before HTTP begins, (c) pushes Response Screen FIRST to own the transition frame budget, (d) commits list mutation + notifyListeners only after new route is on top.
- Canonical double-tap guard: _acceptInFlight Set in provider + local State _accepting flag.
- 409 race-lose wording unified to "This issue has already been taken up" with clearer SnackBar + OK action.

### 4. BUSY Status UI Masking
- Availability banner on dispatch screen always renders green "AVAILABLE (waiting for jobs)".
- Profile screen Availability row masks BUSY -> AVAILABLE.
- Server-side BUSY/AVAILABLE tracking (location PATCH, accept availability check) remains 100% intact.

### 5. Release Engineering
- Bumped pubspec.yaml to 2.6.0+26, Android defaultConfig versionCode=26 versionName=2.6.0.
- Release signing: supports key.properties OR env vars (SIGNALAID_STORE_FILE etc.), falls back cleanly to debug keystore on developer machines.
- Added Android 12+ permissions: USE_EXACT_ALARM, USE_FULL_SCREEN_INTENT, FOREGROUND_SERVICE_SPECIAL_USE, ACCESS_BACKGROUND_LOCATION, VIBRATE, DISABLE_KEYGUARD.
