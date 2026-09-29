import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../providers/company_provider.dart';

class InviteCodeCard extends StatefulWidget {
  const InviteCodeCard({super.key});

  @override
  State<InviteCodeCard> createState() => InviteCodeCardState();
}

class InviteCodeCardState extends State<InviteCodeCard> {
  final _controller = TextEditingController();
  final _submit = SubmitController();
  bool get _busy => _submit.isBusy;

  @override
  void dispose() {
    _submit.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final company = context.read<CompanyProvider>();
    final ok = await _submit.run(
      () => company.acceptInviteCode(_controller.text),
    );
    if (!ok && mounted) showSnack(context, _submit.error!, error: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _submit,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      decoration: const InputDecoration(
        hintText: 'Paste your invitation link',
        prefixIcon: Icon(Icons.link_rounded),
      ),
      onSubmitted: (_) => _join(),
    );
    final button = GradientButton(
      label: 'Join',
      icon: Icons.login_rounded,
      loading: _busy,
      onPressed: _join,
    );
    return AppCard(
      title: 'Joining your team?',
      subtitle:
          'Open the invitation e-mail from your admin, or paste the link here.',
      icon: Icons.group_add_rounded,
      child: context.isPhone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [field, const SizedBox(height: 10), button],
            )
          : Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 10),
                button,
              ],
            ),
    );
  }
}
