import 'package:flutter/material.dart';

import 'app/portal_app.dart';
import 'core/constants/platform_config.dart';
import 'core/constants/supabase_config.dart';
import 'features/auth/data/datasource/auth_service.dart';
import 'features/settings/presentation/providers/preferences_service.dart';
import 'theme/app_theme.dart';

/// Android / iOS: the reporting portal (same as web). Time is tracked by the
/// desktop app; phones are for checking timesheets and managing the team.
///
/// Google sign-in returns through the `timetrak://login-callback` deep link,
/// which supabase_flutter handles automatically.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    PlatformConfig.printPlatformInfo();
    await SupabaseConfig.initialize();

    final authService = AuthService();
    await authService.restoreSession();

    runPortalApp(
      supabaseClient: SupabaseConfig.client,
      authService: authService,
      preferencesService: await PreferencesService.create(),
    );
  } catch (e, stackTrace) {
    debugPrint('[MOBILE] ERROR during initialization: $e\n$stackTrace');
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to start Time Trak',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText('$e', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
