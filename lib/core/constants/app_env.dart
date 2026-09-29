import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime configuration for every platform.
///
/// Values are resolved in this order:
///   1. Compile-time defines — `flutter build … --dart-define-from-file=.env`
///      (used by the build scripts; required for web because hosting does not
///      serve dot-files).
///   2. The bundled `.env` asset — convenient for `flutter run` on desktop.
///
/// See `.env.example` for the list of keys.
class AppEnv {
  AppEnv._();

  static const _defines = <String, String>{
    'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
    'SUPABASE_PUBLISHABLE_KEY': String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
    'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
    'WEB_APP_URL': String.fromEnvironment('WEB_APP_URL'),
    'DESKTOP_DOWNLOAD_URL': String.fromEnvironment('DESKTOP_DOWNLOAD_URL'),
    'OAUTH_CALLBACK_PORT': String.fromEnvironment('OAUTH_CALLBACK_PORT'),
  };

  static bool _loaded = false;

  /// Loads the `.env` asset if present. Safe to call more than once.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      await dotenv.load(isOptional: true);
    } catch (e) {
      debugPrint('[AppEnv] .env asset not loaded: $e');
    }
  }

  static String? _read(String key) {
    final defined = _defines[key];
    if (defined != null && defined.isNotEmpty) return defined;
    if (!dotenv.isInitialized) return null;
    final value = dotenv.maybeGet(key)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  static String _require(String key) {
    final value = _read(key);
    if (value == null) {
      throw StateError(
        'Missing $key. Add it to .env (see .env.example) or pass '
        '--dart-define-from-file=.env when building.',
      );
    }
    return value;
  }

  static String get supabaseUrl => _require('SUPABASE_URL');

  /// Public client key: the new `sb_publishable_…` key or the legacy anon key.
  static String get supabaseKey =>
      _read('SUPABASE_PUBLISHABLE_KEY') ?? _require('SUPABASE_ANON_KEY');

  /// Public URL of the web portal. Used for invitation links and the
  /// "Web Portal" shortcut in the desktop app. On web it defaults to the
  /// current origin.
  static String get webAppUrl {
    final configured = _read('WEB_APP_URL');
    if (configured != null) return configured.replaceAll(RegExp(r'/+$'), '');
    if (kIsWeb) return Uri.base.origin;
    return '';
  }

  /// Where members download the desktop tracker (shown after joining a team).
  static String? get desktopDownloadUrl => _read('DESKTOP_DOWNLOAD_URL');

  /// Localhost port that receives the Google OAuth callback on desktop.
  /// Must match a redirect URL allowed in Supabase → Auth → URL Configuration.
  static int get oauthCallbackPort =>
      int.tryParse(_read('OAUTH_CALLBACK_PORT') ?? '') ?? 3000;
}
