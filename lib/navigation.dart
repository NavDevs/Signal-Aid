import 'package:flutter/material.dart';

/// Global navigator used to unwind pushed routes (response, history, …) when
/// the server is reset while they sit on top of the session gate.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
