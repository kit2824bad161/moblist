import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../providers/moblist_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MobListProvider>();
    final alarmService = provider.alarmService;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Accountability Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Daily Accountability Reminder (Configurable)
          _buildSectionHeader('DAILY ACCOUNTABILITY REMINDER'),
          _buildCard([
            ListTile(
              leading: const Icon(Icons.alarm_rounded, color: AppColors.alarm, size: 28),
              title: const Text(
                'Reminder Time',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Text(
                'Scheduled for ${provider.formattedAlarmTime} every night if any required task is incomplete.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.alarmBg.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.alarm, width: 1),
                ),
                child: Text(
                  provider.formattedAlarmTime,
                  style: const TextStyle(
                    color: AppColors.alarm,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.access_time_rounded, size: 18),
                      label: const Text(
                        'Change Time',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: provider.configuredAlarmTime,
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: AppColors.accent,
                                  surface: AppColors.surface,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null && context.mounted) {
                          await provider.updateAlarmTime(picked);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.completed,
                                content: Text(
                                  'Reminder time updated to ${provider.formattedAlarmTime}. Saved.',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Status: ${alarmService.isAlarmActive ? "ACTIVE (Silence in app, reactivates on exit)" : "SCHEDULED (${provider.formattedAlarmTime})"}\n'
                'Rule: Opening MobList temporarily silences the alarm so you can work. '
                'Leaving the app without completing all required tasks reactivates the alarm. '
                'Completing all 4 required tasks permanently stops the alarm for the day.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Section 2: Core Targets & Rules
          _buildSectionHeader('CORE ACCOUNTABILITY RULES'),
          _buildCard([
            const ListTile(
              leading: Icon(Icons.timer_outlined, color: AppColors.primary),
              title: Text('Daily Target: 10 Minutes',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Every required task requires at least 10 cumulative valid productive minutes (600 seconds) per day.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.hourglass_top_rounded, color: AppColors.grace),
              title: Text('Grace Period: 30 Seconds',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'When visual activity detection is temporarily lost, a 30s grace window protects your session without adding unverified time.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Section 3: Emergency Days System
          _buildSectionHeader('EMERGENCY DAYS ALLOWANCE'),
          _buildCard([
            ListTile(
              leading: const Icon(Icons.shield_rounded, color: AppColors.emergency),
              title: const Text('5 Emergency Days / Month',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Used this month: ${provider.emergencyDaysUsedThisMonth} / 5. Remaining: ${provider.emergencyDaysRemainingThisMonth}. Resets on the 1st of every calendar month.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Section 4: Privacy & Offline Architecture
          _buildSectionHeader('PRIVACY & OFFLINE ARCHITECTURE'),
          _buildCard([
            const ListTile(
              leading: Icon(Icons.offline_pin_rounded, color: AppColors.completed),
              title: Text('100% Offline & Private',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'No internet required. Zero cloud upload. Camera frames are processed exclusively in real-time RAM for ML and released immediately.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Section 5: On-Device ML Model Information
          _buildSectionHeader('ON-DEVICE ML OBJECT DETECTION'),
          _buildCard([
            const ListTile(
              leading: Icon(Icons.memory_rounded, color: AppColors.primary),
              title: Text('Offline SSD MobileNet v1',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Detects Person, Laptop, and Book with zero cloud dependencies or simulations.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ]),

          const SizedBox(height: 24),
          const Center(
            child: Text(
              'MobList v1.0.0 • Personal Accountability Engine',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(children: children),
    );
  }
}
