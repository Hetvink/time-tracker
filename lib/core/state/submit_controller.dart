import 'package:flutter/foundation.dart';

/// Busy / error / info state for a form or action button.
///
/// ```dart
/// final submit = SubmitController();
/// await submit.run(() => repo.save()); // returns an error message or null
/// ListenableBuilder(listenable: submit, builder: ...)
/// ```
class SubmitController extends ChangeNotifier {
  bool _busy = false;
  String? _error;
  String? _info;
  bool _disposed = false;

  bool get isBusy => _busy;
  String? get error => _error;
  String? get info => _info;

  /// Runs [action] (which returns an error message, or null on success)
  /// unless one is already running. Returns true on success.
  Future<bool> run(
    Future<String?> Function() action, {
    String? successInfo,
  }) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _info = null;
    _notify();
    String? error;
    try {
      error = await action();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    _busy = false;
    _error = error;
    _info = error == null ? successInfo : null;
    _notify();
    return error == null;
  }

  void setError(String? message) {
    _error = message;
    _info = null;
    _notify();
  }

  void setInfo(String? message) {
    _info = message;
    _error = null;
    _notify();
  }

  void clear() {
    if (_error == null && _info == null) return;
    _error = null;
    _info = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
