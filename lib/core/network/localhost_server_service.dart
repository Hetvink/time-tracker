import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:time_trak/core/constants/app_env.dart';
import 'package:time_trak/features/auth/data/datasource/auth_service.dart';

class LocalhostServerService {
  final AuthService _authService;
  HttpServer? _server;
  final int port = AppEnv.oauthCallbackPort;

  LocalhostServerService(this._authService);

  /// Start localhost server to handle OAuth callbacks on Windows
  Future<void> startServer() async {
    // If server is already running, stop it first
    if (_server != null) {
      debugPrint('[LocalhostServer] Server already running, stopping first...');
      await stopServer();
      // Wait a bit for the port to be released
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      debugPrint('[LocalhostServer] Listening on http://localhost:$port');

      _server!.listen((HttpRequest request) async {
        final uri = request.uri;
        debugPrint('[LocalhostServer] Received request: $uri');

        // Check if this is an OAuth callback (has code or error parameters)
        // Also check the fragment for parameters (some OAuth flows use fragments)
        final hasCode = uri.queryParameters.containsKey('code');
        final hasAccessToken = uri.queryParameters.containsKey('access_token');
        final hasError = uri.queryParameters.containsKey('error');

        debugPrint(
          '[LocalhostServer] Query Parameters: ${uri.queryParameters}',
        );
        debugPrint('[LocalhostServer] Fragment: ${uri.fragment}');

        if (hasCode || hasAccessToken || hasError) {
          String htmlResponse;
          int statusCode;

          if (hasError) {
            // OAuth error from Supabase/Google
            final error = uri.queryParameters['error'] ?? 'unknown_error';
            final errorDescription =
                uri.queryParameters['error_description'] ?? 'No description';

            debugPrint(
              '[LocalhostServer] OAuth error: $error - $errorDescription',
            );

            statusCode = 400;
            htmlResponse = _buildErrorPage(error, errorDescription);
          } else {
            // Try to handle OAuth callback
            try {
              final callbackUrl = Uri.parse(
                'http://localhost:$port${uri.path}?${uri.query}',
              );
              await _authService.handleOAuthCallback(callbackUrl);

              statusCode = 200;
              htmlResponse = _buildSuccessPage();
            } catch (e) {
              debugPrint('[LocalhostServer] OAuth callback failed: $e');
              statusCode = 500;
              htmlResponse = _buildErrorPage('callback_failed', e.toString());
            }
          }

          // Send response to browser
          request.response
            ..statusCode = statusCode
            ..headers.contentType = ContentType.html
            ..write(htmlResponse);
        } else {
          // Not an OAuth callback
          request.response
            ..statusCode = 404
            ..headers.contentType = ContentType.html
            ..write(_build404Page());
        }

        await request.response.close();
      });
    } on SocketException catch (e) {
      if (e.message.contains('Address already in use')) {
        debugPrint(
          '[LocalhostServer] Port $port is already in use. This is usually safe to ignore - '
          'the server from a previous session is still running and will handle OAuth callbacks.',
        );
        // Don't rethrow - this is not a critical error
        // The existing server will handle callbacks
        return; // Exit gracefully
      } else {
        debugPrint('[LocalhostServer] Failed to start server: $e');
        rethrow;
      }
    } catch (e) {
      debugPrint('[LocalhostServer] Failed to start server: $e');
      // Don't rethrow - allow app to continue even if server fails
      // The app can still function, just won't be able to handle OAuth
      return;
    }
  }

  String _buildSuccessPage() {
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <title>Login Successful</title>
        <meta charset="UTF-8">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          }
          .container {
            background: white;
            padding: 3rem;
            border-radius: 1rem;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 400px;
          }
          h1 {
            color: #667eea;
            margin: 0 0 1rem 0;
            font-size: 2rem;
          }
          p {
            color: #666;
            margin: 0;
            line-height: 1.6;
          }
          .icon {
            font-size: 4rem;
            margin-bottom: 1rem;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="icon">✅</div>
          <h1>Login Successful!</h1>
          <p>Authentication completed successfully.</p>
          <p style="margin-top: 1rem; font-weight: bold;">You can now close this window and return to Time Trak.</p>
        </div>
        <script>
          // Try to close the window automatically after 2 seconds
          setTimeout(() => {
            window.close();
            // If window.close() doesn't work (blocked by browser), show message
            setTimeout(() => {
              document.querySelector('.container').innerHTML =
                '<div class="icon">✅</div>' +
                '<h1>Authentication Complete!</h1>' +
                '<p>Please close this browser window and return to the Time Trak app.</p>' +
                '<p style="margin-top: 1rem; color: #999; font-size: 0.9rem;">If the app doesn\\'t update, try clicking on it.</p>';
            }, 500);
          }, 2000);
        </script>
      </body>
      </html>
    ''';
  }

  String _buildErrorPage(String error, String description) {
    // Decode URL-encoded description
    final decodedDescription = Uri.decodeComponent(
      description.replaceAll('+', ' '),
    );

    String userMessage;
    String technicalDetails;

    if (error == 'server_error' &&
        decodedDescription.contains('Unable to exchange external code')) {
      userMessage = 'Google OAuth Configuration Error';
      technicalDetails = '''
        <p><strong>The issue:</strong> Supabase cannot verify your Google login.</p>
        <p><strong>Why:</strong> Your Google Cloud OAuth client configuration doesn't match Supabase.</p>
        <p><strong>Fix:</strong></p>
        <ol style="text-align: left; margin: 1rem 0;">
          <li>Go to <a href="https://console.cloud.google.com/apis/credentials" target="_blank">Google Cloud Console</a></li>
          <li>Verify your OAuth client type is <strong>Web application</strong> (NOT Desktop)</li>
          <li>Add this redirect URI: <code>https://YOUR-PROJECT.supabase.co/auth/v1/callback</code></li>
          <li>Ensure Client ID and Secret in Supabase match Google Cloud exactly</li>
        </ol>
      ''';
    } else {
      userMessage = 'Authentication Failed';
      technicalDetails = '<p>Error: $error</p><p>$decodedDescription</p>';
    }

    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <title>Login Failed</title>
        <meta charset="UTF-8">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            padding: 2rem;
          }
          .container {
            background: white;
            padding: 3rem;
            border-radius: 1rem;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 600px;
          }
          h1 {
            color: #f5576c;
            margin: 0 0 1rem 0;
            font-size: 2rem;
          }
          p, ol {
            color: #666;
            line-height: 1.6;
          }
          code {
            background: #f5f5f5;
            padding: 0.2rem 0.5rem;
            border-radius: 0.25rem;
            font-family: monospace;
            font-size: 0.9rem;
          }
          .icon {
            font-size: 4rem;
            margin-bottom: 1rem;
            text-align: center;
          }
          a {
            color: #667eea;
            text-decoration: none;
          }
          a:hover {
            text-decoration: underline;
          }
          .button {
            display: inline-block;
            margin-top: 1.5rem;
            padding: 0.75rem 1.5rem;
            background: #667eea;
            color: white;
            border-radius: 0.5rem;
            text-decoration: none;
            font-weight: 600;
          }
          .button:hover {
            background: #5568d3;
            text-decoration: none;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="icon">⚠️</div>
          <h1>$userMessage</h1>
          $technicalDetails
          <a href="#" class="button" onclick="window.close(); return false;">Close Window</a>
        </div>
      </body>
      </html>
    ''';
  }

  String _build404Page() {
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <title>Not Found</title>
        <meta charset="UTF-8">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            background: #f5f5f5;
          }
          .container {
            text-align: center;
            color: #666;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>404 - Not Found</h1>
          <p>This page is only for OAuth callbacks.</p>
        </div>
      </body>
      </html>
    ''';
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    debugPrint('[LocalhostServer] Server stopped');
  }
}
