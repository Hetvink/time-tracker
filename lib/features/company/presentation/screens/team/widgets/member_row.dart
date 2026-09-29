import 'package:flutter/material.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../../admin/presentation/screens/member_profile_page.dart';
import '../../../../data/models/team_member.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class MemberRow extends StatefulWidget {
  final TeamMember member;
  final VoidCallback onOpen;
  final Widget menu;

  const MemberRow({
    super.key,
    required this.member,
    required this.onOpen,
    required this.menu,
  });

  @override
  State<MemberRow> createState() => MemberRowState();
}

class MemberRowState extends State<MemberRow> {
  final _hover = ValueNotifier(false);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _hover,
    builder: (context, hover, _) => _build(context, hover),
  );

  Widget _build(BuildContext context, bool hover) {
    final m = widget.member;
    final (status, color) = memberStatus(m);
    final num = context.text.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return MouseRegion(
      onEnter: (_) => _hover.value = true,
      onExit: (_) => _hover.value = false,
      child: InkWell(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: hover
              ? context.colors.surfaceHover.withValues(alpha: 0.5)
              : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    UserAvatar(
                      name: m.displayName,
                      imageUrl: m.avatarUrl,
                      statusColor: color,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  m.displayName,
                                  style: context.text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (m.isAdmin) ...[
                                const SizedBox(width: 6),
                                const StatusPill(
                                  label: AppStrings.admin,
                                  color: AppColors.warning,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            m.email,
                            style: context.text.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    if (m.isWorking)
                      PulseDot(color: color, size: 7)
                    else
                      const SizedBox(width: 4),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        status,
                        style: context.text.bodyMedium?.copyWith(
                          color: color == AppColors.idle
                              ? context.colors.textMuted
                              : color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatHm(m.today),
                  style: num?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatHm(m.week),
                  style: num,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatHm(m.month),
                  style: num,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              widget.menu,
            ],
          ),
        ),
      ),
    );
  }
}

class MemberCard extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onOpen;
  final Widget menu;

  const MemberCard({
    super.key,
    required this.member,
    required this.onOpen,
    required this.menu,
  });

  @override
  Widget build(BuildContext context) {
    final m = member;
    final (status, color) = memberStatus(m);
    Widget stat(String label, Duration d) => Expanded(
      child: Column(
        children: [
          Text(
            formatHm(d),
            style: context.text.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label, style: context.text.bodySmall),
        ],
      ),
    );
    return TiltCard(
      onTap: onOpen,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: m.displayName,
                  imageUrl: m.avatarUrl,
                  radius: 22,
                  statusColor: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.displayName,
                        style: context.text.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        m.email,
                        style: context.text.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                menu,
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusPill(label: status, color: color, dot: true),
                if (m.isAdmin)
                  const StatusPill(
                    label: AppStrings.admin,
                    color: AppColors.warning,
                    icon: Icons.shield_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: [
                  stat('Today', m.today),
                  stat('Week', m.week),
                  stat('Month', m.month),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Invitations
// =============================================================================
