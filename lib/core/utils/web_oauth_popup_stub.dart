/// Native (non-web) stand-in for `web_oauth_popup.dart`.
/// Selected by the conditional import in `auth_service.dart`.
class WebOAuthPopup {
  static Future<Uri?> openTabAndWaitForCallback({
    required String authUrl,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    throw UnsupportedError('WebOAuthPopup is only supported on web platforms');
  }

  static bool hasOAuthError(Uri uri) => uri.fragment.contains('error');

  static Map<String, String> extractErrorFromUrl(Uri uri) => const {};
}
