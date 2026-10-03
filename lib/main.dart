import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/trips_provider.dart';
import 'navigation.dart';
import 'transitions.dart';
import 'screens/login_screen.dart';
import 'screens/dispatch_screen.dart';
import 'screens/response_screen.dart';
import 'screens/history_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/approval_pending_screen.dart';
import 'screens/profile_screen.dart';
import 'utils/app_colors.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  runApp(const SignalAidApp());
}

class SignalAidApp extends StatelessWidget {
  const SignalAidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TripsProvider(),
      child: MaterialApp(
        title: 'SignalAid',
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          pageTransitionsTheme: appPageTransitions,
          colorScheme: const ColorScheme.dark(
            surface: AppColors.card,
            onSurface: AppColors.cardForeground,
            primary: AppColors.primary,
            onPrimary: AppColors.primaryForeground,
            secondary: AppColors.secondary,
            onSecondary: AppColors.secondaryForeground,
          ),
          scaffoldBackgroundColor: AppColors.background,
          textTheme: GoogleFonts.interTextTheme(
            ThemeData.dark().textTheme,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
          ),
        ),
        home: const SessionGate(),
        routes: {
          '/dispatch': (context) => const DispatchScreen(),
          '/response': (context) => const ResponseScreen(),
          '/history': (context) => const HistoryScreen(),
          '/register': (context) => const RegisterScreen(),
          '/approval': (context) => const ApprovalPendingScreen(),
          '/profile': (context) => const ProfileScreen(),
        },
      ),
    );
  }
}

/// S0 â€” decides which screen the driver belongs on.
///
/// The backend drives this: an approved session reaches the duty dashboard, a
/// pending or rejected registration is parked on the approval screen, and an
/// invalidated session is returned to sign-in. Deep links cannot bypass it
/// because the backend re-checks authorization on every guarded call.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripsProvider>();

    switch (provider.session) {
      case SessionState.booting:
        return SplashScreen(offline: provider.offline);
      case SessionState.signedOut:
        return const LoginScreen();
      case SessionState.pendingApproval:
      case SessionState.rejected:
        return const ApprovalPendingScreen();
      case SessionState.approved:
        return const DispatchScreen();
    }
  }
}
