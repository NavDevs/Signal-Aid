import 'dart:io';

/// Synchronous boot/error log written to %TEMP%\signalaid_boot.log
/// so startup hangs and release-mode crashes are diagnosable
/// without a debugger attached.
void bootLog(String message) {
  try {
    final temp = Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? '.';
    final file = File('$temp/signalaid_boot.log');
    file.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $message\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}
