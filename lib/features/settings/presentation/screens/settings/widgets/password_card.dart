import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/auth/presentation/providers/auth_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class PasswordCard extends StatefulWidget {
  const PasswordCard({super.key});

  @override
  State<PasswordCard> createState() => PasswordCardState();
}

class PasswordCardState extends State<PasswordCard> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  final _submit = SubmitController();
  final _obscure = ValueNotifier(true);

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    _submit.dispose();
    _obscure.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await _submit.run(() => auth.changePassword(_pw.text));
    if (ok) {
      _pw.clear();
      _confirm.clear();
    }
    if (mounted) {
      showSnack(context, ok ? 'Password updated' : _submit.error!, error: !ok);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_submit, _obscure]),
    builder: (context, _) => _build(context, _obscure.value, _submit.isBusy),
  );

  Widget _build(BuildContext context, bool obscure, bool busy) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _pw,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () => _obscure.value = !obscure,
              ),
            ),
            validator: (v) =>
                (v?.length ?? 0) < 8 ? 'Use at least 8 characters' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
            validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GradientButton(
              label: AppStrings.updatePassword,
              icon: Icons.key_rounded,
              loading: busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// Company membership row in the Account section.
