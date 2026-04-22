import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/trips_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dispatch_screen.dart';
import 'screens/response_screen.dart';
import 'screens/history_screen.dart';
import 'utils/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('Flutter error: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };
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
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
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
        initialRoute: '/',
        routes: {
          '/': (context) => const LoginScreen(),
          '/dispatch': (context) => const DispatchScreen(),
          '/response': (context) => const ResponseScreen(),
          '/history': (context) => const HistoryScreen(),
        },
      ),
    );
  }
}
