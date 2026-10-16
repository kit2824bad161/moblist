import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../models/daily_task_record_model.dart';

class TaskCard extends StatelessWidget {
  final DailyTaskRecordModel record;
  final VoidCallback onStart;

  const TaskCard({
    super.key,
    required this.record,
    required this.onStart,
  });

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'book':
        return Icons.menu_book_rounded;
      case 'code':
        return Icons.terminal_rounded;
      case 'laptop':
        return Icons.laptop_mac_rounded;
      case 'mic':
        return Icons.mic_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = record.task;
    final isCompleted = record.isCompleted;
    final isCamera = task?.isCameraTask ?? false;
    final progress = record.progressRatio;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isCompleted ? AppColors.completedBg.withOpacity(0.15) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted ? AppColors.completed : AppColors.surfaceBorder,
          width: isCompleted ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Title + Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.completed.withOpacity(0.2)
                      : AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getIconData(task?.iconName ?? 'custom'),
                  color: isCompleted ? AppColors.completed : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task?.name ?? 'Task',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (isCamera) ...[
                          const Icon(Icons.camera_alt_outlined,
                              size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          const Text(
                            'Camera + ML',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ] else ...[
                          const Icon(Icons.timer_outlined,
                              size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          const Text(
                            'Manual Timer',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.completed.withOpacity(0.2)
                      : (record.accumulatedSeconds > 0
                          ? AppColors.active.withOpacity(0.15)
                          : AppColors.surfaceLight),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCompleted) ...[
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.completed, size: 14),
                      const SizedBox(width: 4),
                      const Text(
                        'Completed',
                        style: TextStyle(
                          color: AppColors.completed,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ] else if (record.accumulatedSeconds > 0) ...[
                      const Icon(Icons.play_arrow_rounded,
                          color: AppColors.active, size: 14),
                      const SizedBox(width: 4),
                      const Text(
                        'In Progress',
                        style: TextStyle(
                          color: AppColors.active,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Not Completed',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Progress Row: Time + Progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                record.formattedProgress,
                style: TextStyle(
                  color: isCompleted ? AppColors.completed : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? AppColors.completed : AppColors.primary,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Action button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isCompleted
                    ? AppColors.surfaceLight
                    : (record.accumulatedSeconds > 0
                        ? AppColors.active
                        : AppColors.primary),
                foregroundColor: isCompleted ? AppColors.completed : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onStart,
              icon: Icon(
                isCompleted
                    ? Icons.replay_rounded
                    : (record.accumulatedSeconds > 0
                        ? Icons.play_arrow_rounded
                        : Icons.play_arrow_rounded),
                size: 18,
              ),
              label: Text(
                isCompleted
                    ? 'Start Again (Completed ✓)'
                    : (record.accumulatedSeconds > 0 ? 'RESUME TASK' : 'START TASK'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
