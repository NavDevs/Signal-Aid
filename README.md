# 🚨 Signal Aid

<p align="center">
  <img src="assets/images/icon.png" width="150" height="150" alt="Signal Aid App Icon">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.27-blue?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.6-blue?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Android-API%2021+-green?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License">
  <img src="https://img.shields.io/badge/Version-1.0.12-orange" alt="Version">
</p>

<p align="center">
  <strong><a href="https://navdevs.github.io/Signal-Aid/">🌐 Visit the Official Website</a></strong>
</p>

## 📱 Description

**Signal Aid** is an emergency response system mobile application built with Flutter. Originally converted from a React Native/Expo project, this app helps emergency vehicle drivers navigate through traffic with ML-powered signal preemption, reducing response times and improving public safety.

The app features real-time dispatch planning, criticality-based route optimization, trip history tracking, and intersection preemption status monitoring.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔐 **Driver Authentication** | Secure login with Driver ID and Vehicle Number |
| 🗺️ **Dispatch Planning** | Real-time route planning with ETA calculation |
| ⚡ **Criticality Selection** | Choose between Normal, High, and Critical emergency levels |
| 🚦 **Signal Preemption** | ML-powered traffic signal clearing for emergency vehicles (simulation) |
| ⏱️ **Live Response Tracking** | Real-time countdown timer with intersection status updates |
| 📡 **Live Dispatch Updates** | Socket.IO pushes new emergency requests the moment a citizen reports them |
| 🛡️ **Server-Reset Protection** | Detects backend data wipes (`dataEpoch` / `data_reset`) and signs the driver out with a clear notice |
| ⏱️ **Live Response Tracking** | Real-time countdown timer with intersection status updates |
| 📊 **Trip History** | Complete log of all emergency responses with statistics |
| 🌙 **Dark Theme** | Eye-friendly dark UI optimized for emergency vehicle use |
| 💾 **Local Storage** | Persistent data storage using SharedPreferences |

---

## 🛠️ Tech Stack

| Category | Technology |
|----------|------------|
| **Framework** | Flutter 3.27 |
| **Language** | Dart 3.6 |
| **State Management** | Provider |
| **Local Storage** | SharedPreferences |
| **Fonts** | Google Fonts (Inter) |
| **Icons** | Material Icons |
| **Build Tool** | Gradle 8.12 |

---

## 📁 Project Structure

```
signalaid_flutter/
├── android/                    # Android platform files
├── assets/
│   └── images/
│       └── icon.png            # App icon
├── lib/
│   ├── main.dart               # App entry point + session gate
│   ├── navigation.dart         # Global navigator key / routing
│   ├── config/
│   │   └── supabase_config.dart # Supabase URL/anon-key placeholders
│   ├── models/
│   │   ├── driver.dart         # Driver model
│   │   ├── intersection.dart   # Intersection & DispatchPlan models
│   │   └── trip.dart           # Trip & Criticality models
│   ├── providers/
│   │   └── trips_provider.dart # State management, session, realtime
│   ├── services/
│   │   ├── auth_service.dart   # Register / login / token storage
│   │   ├── dispatch_service.dart # Emergency dispatch API calls
│   │   ├── realtime_service.dart # Socket.IO connection
│   │   └── trip_service.dart   # Trip start/location/status API
│   ├── screens/
│   │   ├── splash_screen.dart        # Boot + session restore
│   │   ├── login_screen.dart         # Driver login
│   │   ├── register_screen.dart      # Driver registration
│   │   ├── approval_pending_screen.dart # Awaiting admin approval
│   │   ├── dispatch_screen.dart      # Dispatch planning
│   │   ├── response_screen.dart      # Active response tracking
│   │   ├── history_screen.dart       # Trip history
│   │   └── profile_screen.dart       # Driver profile / sign-out
│   ├── utils/
│   │   ├── app_colors.dart     # Color constants
│   │   ├── boot_log.dart       # Boot diagnostics
│   │   └── dispatch_helper.dart # Business logic
│   └── widgets/
│       ├── card.dart           # Reusable card component
│       ├── criticality_picker.dart # Severity selector
│       ├── motion.dart         # Entry animations
│       ├── primary_button.dart # Button component
│       └── stat.dart           # Statistics display
├── pubspec.yaml                # Dependencies & configuration
└── README.md                   # This file
```

---

## ⚙️ Configuration

| What | Where |
|------|-------|
| Backend URL (`baseUrl`) | `lib/providers/trips_provider.dart` — hosted ClearPath server (`https://clearpath-server.onrender.com`) |
| Supabase project | `lib/config/supabase_config.dart` — fill in your own `url` / `anonKey` placeholders (optional, for photo storage) |
| Colors / theme | `lib/utils/app_colors.dart` |

No service-role secrets ship in the app — drivers authenticate with Driver ID + vehicle number against the backend, and the session stays on-device.

---

## 🚀 Installation

### Prerequisites

- Flutter SDK 3.27 or higher
- Dart SDK 3.6 or higher
- Android Studio / VS Code
- Android SDK (API 21+)

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/NavDevs/Signal-Aid.git
   cd Signal-Aid
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

---

## 📦 Build Commands

### Debug Build
```bash
flutter build apk --debug
```

### Release Build
```bash
flutter build apk --release
```

### Build App Bundle (for Play Store)
```bash
flutter build appbundle
```

**Output Location:** `build/app/outputs/flutter-apk/app-release.apk`

---

## ⬇️ Direct Download

<p align="center">
  <a href="https://github.com/NavDevs/Signal-Aid/releases/download/v1.0.12/SignalAid-v1.0.12-final.apk">
    <img src="https://img.shields.io/badge/Download-Latest%20APK-brightgreen?logo=android" alt="Download APK" width="200">
  </a>
</p>

**Minimum Requirements:**
- Android 5.0 (API Level 21) or higher
- 60MB free storage space

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Author

**Signal Aid Team**

<p align="center">
  Made with ❤️ for emergency responders
</p>

---

## 🙏 Acknowledgments

- Original React Native/Expo project inspiration
- Flutter Team for the amazing framework
- All emergency responders who keep us safe

---

<p align="center">
  <strong>⭐ Star this repository if you found it helpful!</strong>
</p>
