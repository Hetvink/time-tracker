import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'app/portal_app.dart';
import 'core/constants/platform_config.dart';
import 'core/constants/supabase_config.dart';
import 'features/auth/data/datasource/auth_service.dart';
import 'features/company/presentation/providers/company_provider.dart';
import 'features/settings/presentation/providers/preferences_service.dart';
import 'theme/app_theme.dart';
import 'package:time_trak/core/constants/app_strings.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final uri = Uri.base;
    final hasOAuthResult =
        uri.fragment.contains('access_token') || uri.fragment.contains('error');

    // This tab was opened only to finish Google sign-in. web/index.html has
    // already relayed the result to the main tab; just close it.
    if (web.window.opener != null && hasOAuthResult) {
      runApp(const OAuthCallbackScreen());
      return;
    }

    // Invitation link: remember the token through sign-in, then tidy the URL
    await _captureInviteToken(uri);

    PlatformConfig.printPlatformInfo();
    await SupabaseConfig.initialize();

    final (oauthError, oauthErrorDescription) = _parseOAuthError(uri);
    final authService = AuthService();

    // Picks up an existing session (and updates last login)
    await authService.restoreSession();

    runPortalApp(
      supabaseClient: SupabaseConfig.client,
      authService: authService,
      preferencesService: await PreferencesService.create(),
      oauthError: oauthError,
      oauthErrorDescription: oauthErrorDescription,
      onClearOAuthError: () => web.window.history.replaceState(null, '', '/'),
    );
  } catch (e, stackTrace) {
    debugPrint('[WEB] ERROR during initialization: $e\n$stackTrace');
    runApp(_InitErrorApp(error: e));
  }
}

Future<void> _captureInviteToken(Uri uri) async {
  final token = CompanyProvider.extractInviteToken(uri.toString());
  if (token == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_invite_token', token);
  } catch (e) {
    debugPrint('[WEB] Could not store invite token: $e');
  }
  web.window.history.replaceState(null, '', uri.path.isEmpty ? '/' : uri.path);
}

(String?, String?) _parseOAuthError(Uri uri) {
  if (!uri.fragment.contains('error')) return (null, null);
  final params = Uri.splitQueryString(uri.fragment);
  return (params['error'], params['error_description']);
}

class _InitErrorApp extends StatelessWidget {
  final Object error;
  const _InitErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to start Time Trak',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => web.window.location.reload(),
                  child: const Text(AppStrings.reload),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in the sign-in tab after Google redirects back.
class OAuthCallbackScreen extends StatefulWidget {
  const OAuthCallbackScreen({super.key});

  @override
  State<OAuthCallbackScreen> createState() => _OAuthCallbackScreenState();
}

class _OAuthCallbackScreenState extends State<OAuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), () => web.window.close());
  }

  @override
  Widget build(BuildContext context) {
    final hasError = Uri.base.fragment.contains('error');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasError ? Icons.error_outline : Icons.check_circle_outline,
                  size: 72,
                  color: hasError ? Colors.red : Colors.green,
                ),
                const SizedBox(height: 16),
                Text(
                  hasError ? 'Sign-in failed' : 'Signed in',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(AppStrings.youCanCloseThisTabAndReturnToTimeTrak),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => web.window.close(),
                  child: const Text(AppStrings.closeTab),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
