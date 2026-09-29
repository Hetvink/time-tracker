import 'dart:io' show Platform;

import 'main_desktop.dart' as desktop;
import 'main_mobile.dart' as mobile;

/// Native entry: phones run the portal, computers run the tracker.
Future<void> main() =>
    Platform.isAndroid || Platform.isIOS ? mobile.main() : desktop.main();
