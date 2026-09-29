import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/ui_kit.dart';
import '../../../../theme/macos_theme.dart';
import '../../../auth/data/models/user_role.dart';
import '../../data/models/company_invitation.dart';
import '../../data/repository/company_repository.dart';

/// Invite one or more people by e-mail. Returns true if anything was sent.
Future<bool> showInviteMemberDialog(
  BuildContext context, {
  required CompanyRepository repository,
  required String companyId,
  required String companyName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => _InviteController(repository, companyId),
      child: _InviteMemberDialog(companyName: companyName),
    ),
  );
  return result ?? false;
}

class _InviteOutcome {
  final String email;
  final InviteResult? result;
  final String? error;
  const _InviteOutcome(this.email, {this.result, this.error});
}

/// Form + sending state of the invite dialog.
class _InviteController extends ChangeNotifier {
  final CompanyRepository repository;
  final String companyId;
  _InviteController(this.repository, this.companyId);

  final emails = TextEditingController();
  UserRole _role = UserRole.member;
  bool _sending = false;
  List<_InviteOutcome>? _outcomes;
  String? _inputError;
  bool _disposed = false;

  UserRole get role => _role;
  bool get isSending => _sending;
  List<_InviteOutcome>? get outcomes => _outcomes;
  String? get inputError => _inputError;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void setRole(UserRole role) {
    _role = role;
    _notify();
  }

  List<String> _parseEmails() => emails.text
      .split(RegExp(r'[\s,;]+'))
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  Future<void> send() async {
    final list = _parseEmails();
    final invalid = list.where((e) => !_emailPattern.hasMatch(e)).toList();
    if (list.isEmpty || invalid.isNotEmpty) {
      _inputError = list.isEmpty
          ? 'Enter at least one e-mail address'
          : 'Invalid: ${invalid.join(', ')}';
      _notify();
      return;
    }

    _sending = true;
    _inputError = null;
    _notify();

    final outcomes = <_InviteOutcome>[];
    for (final email in list) {
      try {
        final result = await repository.inviteMember(
          email: email,
          role: _role,
          companyId: companyId,
        );
        outcomes.add(_InviteOutcome(email, result: result));
      } catch (e) {
        outcomes.add(_InviteOutcome(email, error: friendlyError(e)));
      }
    }

    _sending = false;
    _outcomes = outcomes;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    emails.dispose();
    super.dispose();
  }
}

class _InviteMemberDialog extends StatelessWidget {
  final String companyName;
  const _InviteMemberDialog({required this.companyName});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<_InviteController>();
    final outcomes = c.outcomes;
    return AlertDialog(
      title: Text(outcomes == null ? 'Invite to $companyName' : 'Invitations'),
      content: SizedBox(
        width: 480,
        child: outcomes == null
            ? _buildForm(context, c)
            : _buildResults(outcomes),
      ),
      actions: outcomes == null
          ? [
              TextButton(
                onPressed: c.isSending
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: c.isSending ? null : c.send,
                icon: c.isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send invites'),
              ),
            ]
          : [
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  outcomes.any((o) => o.result != null),
                ),
                child: const Text('Done'),
              ),
            ],
    );
  }

  Widget _buildForm(BuildContext context, _InviteController c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: c.emails,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'E-mail addresses',
            hintText: 'alex@company.com, sam@company.com',
            helperText: 'Separate several addresses with commas or new lines.',
            errorText: c.inputError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<UserRole>(
          segments: const [
            ButtonSegment(
              value: UserRole.member,
              label: Text('Member'),
              icon: Icon(Icons.person_outline_rounded),
            ),
            ButtonSegment(
              value: UserRole.admin,
              label: Text('Admin'),
              icon: Icon(Icons.admin_panel_settings_outlined),
            ),
          ],
          selected: {c.role},
          onSelectionChanged: (s) => c.setRole(s.first),
        ),
        const SizedBox(height: 8),
        Text(
          c.role == UserRole.admin
              ? 'Admins can invite people and see everyone\'s tracked time.'
              : 'Members track their own time with the desktop app.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildResults(List<_InviteOutcome> outcomes) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: outcomes.length,
        separatorBuilder: (_, _) => const Divider(height: 16),
        itemBuilder: (context, i) {
          final o = outcomes[i];
          final r = o.result;
          final url = r?.inviteUrl;
          final (IconData icon, Color color, String status) = r == null
              ? (
                  Icons.error_outline_rounded,
                  MacOSTheme.systemRed,
                  o.error ?? 'Failed',
                )
              : r.emailSent
              ? (
                  Icons.mark_email_read_outlined,
                  MacOSTheme.systemGreen,
                  'Invitation e-mailed',
                )
              : (
                  Icons.link_rounded,
                  MacOSTheme.systemOrange,
                  r.emailError ?? 'Share the link below',
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      o.email,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 4),
                child: Text(
                  status,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
              if (url != null)
                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        showSnack(context, 'Invite link copied');
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy invite link'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
