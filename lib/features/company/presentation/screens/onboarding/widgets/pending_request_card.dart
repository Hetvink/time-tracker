import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/company.dart';
import '../../../providers/company_provider.dart';

class PendingRequestCard extends StatefulWidget {
  final Company request;
  const PendingRequestCard({required this.request});

  @override
  State<PendingRequestCard> createState() => PendingRequestCardState();
}

class PendingRequestCardState extends State<PendingRequestCard> {
  final _submit = SubmitController();
  bool get _busy => _submit.isBusy;

  @override
  void dispose() {
    _submit.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    final ok = await confirmAction(
      context,
      title: 'Cancel request?',
      message:
          'Your registration for ${widget.request.name} will be withdrawn.',
      confirmLabel: 'Cancel request',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final company = context.read<CompanyProvider>();
    final cancelled = await _submit.run(
      () => company.cancelRequest(widget.request.id),
    );
    if (!cancelled && mounted) showSnack(context, _submit.error!, error: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _submit,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final r = widget.request;
    return SurfaceCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.warning,
                size: 50,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: context.text.titleLarge),
                    Text(
                      'Submitted ${formatDate(r.createdAt)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              const StatusPill(
                label: 'Pending review',
                color: AppColors.warning,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress steps
          const Steps(
            current: 1,
            labels: ['Submitted', 'In review', 'Approved'],
          ),
          const SizedBox(height: 16),
          Text(
            'You get access to the team dashboard as soon as a platform admin approves the request. Pull to refresh or tap refresh to check.',
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('Cancel request'),
            ),
          ),
        ],
      ),
    );
  }
}

class Steps extends StatelessWidget {
  final int current;
  final List<String> labels;
  const Steps({required this.current, required this.labels});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: i <= current ? AppColors.brandGradient : null,
                  color: i <= current ? null : colors.surfaceHover,
                ),
                child: Icon(
                  i < current ? Icons.check_rounded : Icons.circle,
                  size: i < current ? 16 : 8,
                  color: i <= current ? Colors.white : colors.textSubtle,
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[i], style: context.text.labelSmall),
            ],
          ),
          if (i < labels.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
                color: i < current ? AppColors.primary : colors.surfaceHover,
              ),
            ),
        ],
      ],
    );
  }
}
