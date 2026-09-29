import 'package:flutter/material.dart';

import 'auth_provider.dart';

enum LoginMode { signIn, signUp }

/// All state of the sign-in / sign-up card: mode, fields, busy flag and the
/// error / info banner. Auth itself is delegated to [AuthProvider].
class LoginFormController extends ChangeNotifier {
  final AuthProvider auth;
  LoginFormController(this.auth);

  static final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  LoginMode _mode = LoginMode.signIn;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _info;
  bool _disposed = false;

  LoginMode get mode => _mode;
  bool get isSignUp => _mode == LoginMode.signUp;
  bool get obscure => _obscure;
  bool get isBusy => _busy;
  String? get error => _error;
  String? get info => _info;

  void setMode(LoginMode mode) {
    _mode = mode;
    _error = null;
    _info = null;
    _notify();
  }

  void toggleObscure() {
    _obscure = !_obscure;
    _notify();
  }

  /// Validates the form, then signs in or up.
  Future<void> submit() async {
    _error = null;
    _info = null;
    _notify();
    if (!(formKey.currentState?.validate() ?? false) || _busy) return;

    _busy = true;
    _notify();
    final signUp = isSignUp;
    final fullName = name.text.trim();
    final ok = signUp
        ? await auth.signUpWithEmailPassword(
            email.text.trim(),
            password.text,
            name: fullName.isEmpty ? null : fullName,
          )
        : await auth.signInWithEmailPassword(email.text.trim(), password.text);
    _busy = false;
    if (!ok) {
      _error = auth.errorMessage ?? 'Authentication failed. Please try again.';
    } else if (signUp && !auth.isAuthenticated) {
      _info = 'Check your inbox to confirm your e-mail, then sign in.';
      _mode = LoginMode.signIn;
    }
    _notify();
  }

  Future<void> signInWithGoogle() async {
    if (_busy) return;
    _error = null;
    _busy = true;
    _notify();
    final ok = await auth.signInWithGoogle();
    _busy = false;
    if (!ok) _error = auth.errorMessage ?? 'Google sign-in failed.';
    _notify();
  }

  Future<void> sendPasswordReset(String address) async {
    if (!emailPattern.hasMatch(address)) {
      _error = 'Enter a valid e-mail address.';
      _info = null;
      _notify();
      return;
    }
    final error = await auth.sendPasswordReset(address);
    _error = error;
    _info = error == null ? 'Reset link sent to $address.' : null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }
}
