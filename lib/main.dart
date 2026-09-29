// ============================================================
// TIME TRAK - MAIN ENTRY POINT
// ============================================================
// - Web:      main_web.dart     (reporting portal)
// - Android/iOS: main_mobile.dart (reporting portal)
// - macOS/Windows/Linux: main_desktop.dart (background tracker)
// ============================================================

import 'main_io.dart'
    if (dart.library.js_interop) 'main_web.dart'
    as platform_main;

Future<void> main() => platform_main.main();
