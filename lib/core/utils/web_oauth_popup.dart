import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Web-only helpers for the Google OAuth tab flow.
///
/// Import through the conditional import in `auth_service.dart`; native
/// platforms get `web_oauth_popup_stub.dart` instead.
class WebOAuthPopup {
  /// Opens [authUrl] in a new tab and waits for the callback URL.
  ///
  /// `web/index.html` detects the OAuth redirect in that tab and posts the
  /// callback URL on the `oauth_callback_channel` BroadcastChannel.
  ///
  /// Returns null if the user closes the tab before finishing.
  static Future<Uri?> openTabAndWaitForCallback({
    required String authUrl,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    debugPrint('[WebOAuthPopup] Opening OAuth in new tab');

    final channel = web.BroadcastChannel('oauth_callback_channel');
    final completer = Completer<Uri?>();

    final messageListener = ((web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is Map && data['type'] == 'oauth_callback') {
        final callbackUrl = data['url'] as String?;
        if (callbackUrl != null && !completer.isCompleted) {
          debugPrint('[WebOAuthPopup] ✅ OAuth callback received');
          completer.complete(Uri.parse(callbackUrl));
        }
      }
    }).toJS;
    channel.addEventListener('message', messageListener);

    // Marker so the OAuth tab knows to close itself after the callback
    final parsed = Uri.parse(authUrl);
    final authUrlWithMarker = parsed.replace(
      queryParameters: {...parsed.queryParameters, '_oauth_tab': 'true'},
    );

    final newTab = web.window.open(authUrlWithMarker.toString(), '_blank');

    Timer? timeoutTimer;
    Timer? checkClosedTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      checkClosedTimer?.cancel();
      channel.removeEventListener('message', messageListener);
      channel.close();
    }

    if (newTab == null) {
      cleanup();
      throw StateError(
        'The sign-in tab was blocked. Allow pop-ups for this site and try again.',
      );
    }

    checkClosedTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (newTab.closed && !completer.isCompleted) {
        debugPrint('[WebOAuthPopup] OAuth tab was closed by user');
        completer.complete(null);
      }
    });

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        try {
          newTab.close();
        } catch (_) {}
        completer.completeError(
          TimeoutException('OAuth tab timed out after $timeout'),
        );
      }
    });

    try {
      return await completer.future;
    } finally {
      cleanup();
    }
  }

  /// Whether the callback URL carries an OAuth error.
  static bool hasOAuthError(Uri uri) => uri.fragment.contains('error');

  /// Extracts `error` / `error_description` from the callback fragment.
  static Map<String, String> extractErrorFromUrl(Uri uri) {
    if (uri.fragment.isEmpty) return {};
    final params = Uri.splitQueryString(uri.fragment);
    return {
      for (final key in const ['error', 'error_description'])
        if (params[key] != null) key: params[key]!,
    };
  }
}
