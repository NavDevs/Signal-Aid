const fs = require('fs');
let content = fs.readFileSync('lib/providers/trips_provider.dart', 'utf8');

// Remove import
content = content.replace(/import '\.\.\/services\/notification_service\.dart';\r?\n/, '');

// Remove startPolling block
content = content.replace(/[ \t]*\/\/ Register background polling[\s\S]*?if \(merged\.token != null && merged\.vehicleType != null\) \{[\s\S]*?NotificationService\.instance\.startPolling\([\s\S]*?\);[\s\S]*?\}/, '');

// Remove stopPolling block
content = content.replace(/[ \t]*\/\/ Stop background polling[\s\S]*?await NotificationService\.instance\.stopPolling\(\);\r?\n/, '');

// Remove showDispatchNotification block
content = content.replace(/[ \t]*\/\/ Fire a local notification[\s\S]*?final d = _driver;[\s\S]*?if \(d != null && d\.driverId\.isNotEmpty && \(d\.vehicleType \?\? ''\)\.isNotEmpty\) \{[\s\S]*?NotificationService\.instance\.showDispatchNotification\([\s\S]*?\);[\s\S]*?\}/, '');

fs.writeFileSync('lib/providers/trips_provider.dart', content, 'utf8');
console.log('Cleaned trips_provider.dart');
