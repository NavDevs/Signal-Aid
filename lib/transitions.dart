import 'package:flutter/material.dart';

/// App-wide page transition: a soft fade with a short upward slide.
///
/// Clean, professional motion (easeOutCubic out, easeInCubic back) instead of
/// the stock platform push. Wired into [MaterialApp.pageTransitionsTheme], so
/// every MaterialPageRoute — named routes and pushes alike — uses it with no
/// call-site changes.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}

/// The [PageTransitionsTheme] applied by the app's MaterialApp.
const PageTransitionsTheme appPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.iOS: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
    TargetPlatform.macOS: AppPageTransitionsBuilder(),
    TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
  },
);
