import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';

class DashboardTimer extends StatelessWidget {
  final Duration initialDuration;
  final bool isRunning;

  const DashboardTimer({
    super.key,
    required this.initialDuration,
    required this.isRunning,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRunning) {
      return _buildSeparatedTimer(context, initialDuration);
    }
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        final currentDuration = provider.state.totalWorkTime;
        return _buildSeparatedTimer(
          context,
          currentDuration > Duration.zero ? currentDuration : initialDuration,
        );
      },
    );
  }

  Widget _buildSeparatedTimer(BuildContext context, Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTimeBox(context, hours, 'HOURS'),
        const SizedBox(width: 8),
        Text(
          ':',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white38,
          ),
        ),
        const SizedBox(width: 8),
        _buildTimeBox(context, minutes, 'MINUTES'),
        const SizedBox(width: 8),
        Text(
          ':',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white38,
          ),
        ),
        const SizedBox(width: 8),
        _buildTimeBox(context, seconds, 'SECONDS'),
      ],
    );
  }

  Widget _buildTimeBox(BuildContext context, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E), // Darker timer background
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFeatures: [const FontFeature.tabularFigures()],
              fontSize: 48,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
