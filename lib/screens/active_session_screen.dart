import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../models/daily_task_record_model.dart';
import '../models/vision_state.dart';
import '../services/timer_engine.dart';
import '../providers/moblist_provider.dart';

class ActiveSessionScreen extends StatefulWidget {
  final DailyTaskRecordModel record;

  const ActiveSessionScreen({super.key, required this.record});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  bool _isStopping = false;
  bool _showDebugPanel = false;
  bool _hasAutoCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MobListProvider>();
      provider.startSession(widget.record);
      provider.timerEngine.addListener(_onTimerTick);
    });
  }

  void _onTimerTick() {
    if (!mounted) return;
    final timerEngine = context.read<MobListProvider>().timerEngine;
    if (timerEngine.isCompleted && !_hasAutoCompleted && !_isStopping) {
      _hasAutoCompleted = true;
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.completed,
              content: Text('🎉 10:00 Target Reached! Task marked as completed.',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          );
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    try {
      context.read<MobListProvider>().timerEngine.removeListener(_onTimerTick);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _handleStopSession() async {
    if (_isStopping) return;
    setState(() => _isStopping = true);
    await context.read<MobListProvider>().stopSessionManually();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MobListProvider>();
    final timerEngine = provider.timerEngine;

    return ListenableBuilder(
      listenable: timerEngine,
      builder: (context, _) {
        final state = timerEngine.state;
        final isCameraTask = widget.record.task?.isCameraTask ?? false;
        final totalSeconds = timerEngine.totalAccumulatedSeconds;
        final isCompleted = timerEngine.isCompleted;

        final curMinutes = totalSeconds ~/ 60;
        final curSecs = totalSeconds % 60;
        final targetMinutes = (widget.record.task?.targetSeconds ?? 600) ~/ 60;
        final targetSecs = (widget.record.task?.targetSeconds ?? 600) % 60;

        final timeString =
            '${curMinutes.toString().padLeft(2, '0')}:${curSecs.toString().padLeft(2, '0')} / '
            '${targetMinutes.toString().padLeft(2, '0')}:${targetSecs.toString().padLeft(2, '0')}';

        final progressRatio = (totalSeconds / (widget.record.task?.targetSeconds ?? 600)).clamp(0.0, 1.0);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              await _handleStopSession();
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () {
                  setState(() => _showDebugPanel = !_showDebugPanel);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_showDebugPanel
                          ? 'Developer ML Debug Mode Activated'
                          : 'Developer ML Debug Mode Hidden'),
                      duration: const Duration(milliseconds: 1500),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Text(widget.record.task?.name ?? 'Active Task'),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleStopSession,
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  // Main Visual Zone (Camera Preview or Manual Timer Graphic)
                  Expanded(
                    flex: 5,
                    child: isCameraTask
                        ? _buildCameraVisionView(context, provider)
                        : _buildManualTimerView(context, provider),
                  ),

                  // Bottom Control Panel
                  Expanded(
                    flex: 4,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        border: Border(
                          top: BorderSide(color: AppColors.surfaceBorder),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Status state chip & countdown
                          _buildStateHeader(state, timerEngine),

                          // Large Time Display (updates LIVE every second)
                          Column(
                            children: [
                              Text(
                                timeString,
                                style: TextStyle(
                                  color: isCompleted ? AppColors.completed : AppColors.textPrimary,
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isCompleted
                                    ? '✓ Completed (10 minutes target reached!)'
                                    : '${(widget.record.task?.targetSeconds ?? 600) - totalSeconds} seconds remaining today',
                                style: TextStyle(
                                  color: isCompleted ? AppColors.completed : AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progressRatio,
                                  minHeight: 10,
                                  backgroundColor: AppColors.surfaceLight,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isCompleted ? AppColors.completed : AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Stop / Completion Action Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCompleted ? AppColors.completed : AppColors.alarm,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _handleStopSession,
                              icon: Icon(
                                isCompleted ? Icons.check_circle_outline : Icons.stop_circle_outlined,
                                size: 22,
                              ),
                              label: Text(
                                isCompleted
                                    ? 'DONE (10 Min Completed)'
                                    : (isCameraTask ? 'STOP CAMERA' : 'SAVE & EXIT'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateHeader(ProductiveState state, TimerEngine timerEngine) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;
    String subText;

    switch (state) {
      case ProductiveState.productive:
        badgeColor = AppColors.completed;
        badgeIcon = Icons.check_circle_rounded;
        badgeText = 'Activity verified';
        subText = 'You can continue working.';
        break;
      case ProductiveState.gracePeriod:
        badgeColor = AppColors.grace;
        badgeIcon = Icons.hourglass_top_rounded;
        badgeText = 'Activity temporarily unavailable';
        subText = 'Please return to your normal position.';
        break;
      case ProductiveState.paused:
        badgeColor = AppColors.paused;
        badgeIcon = Icons.pause_circle_outline_rounded;
        badgeText = 'Activity paused';
        subText = 'Resume activity to continue accumulating time.';
        break;
      case ProductiveState.completed:
        badgeColor = AppColors.completed;
        badgeIcon = Icons.check_circle_rounded;
        badgeText = 'Activity completed';
        subText = 'Daily target of 10 valid minutes achieved!';
        break;
      case ProductiveState.cameraStarting:
        badgeColor = AppColors.primary;
        badgeIcon = Icons.videocam_outlined;
        badgeText = 'Starting camera...';
        subText = 'Position yourself in front of the camera.';
        break;
      case ProductiveState.verifying:
        badgeColor = AppColors.accent;
        badgeIcon = Icons.center_focus_strong_rounded;
        badgeText = 'Verifying activity...';
        subText = 'Position yourself in front of the camera.';
        break;
      default:
        badgeColor = AppColors.textMuted;
        badgeIcon = Icons.info_outline;
        badgeText = 'Ready';
        subText = 'Position yourself in front of the camera.';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        children: [
          Icon(badgeIcon, color: badgeColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                if (subText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subText,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraVisionView(BuildContext context, MobListProvider provider) {
    final cameraService = provider.cameraService;
    final visionResult = provider.timerEngine.lastVisionResult;
    final isBook = widget.record.taskId == AppConstants.defaultTaskIdReadBook;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          if (cameraService.isInitialized && cameraService.controller != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: CameraPreview(cameraService.controller!),
                  ),
                  // Bounding boxes are ONLY painted in developer debug mode
                  if (_showDebugPanel && visionResult.rawDetections.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: BoundingBoxPainter(
                          detections: visionResult.rawDetections,
                          isFrontCamera: cameraService.isFrontCamera,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isBook ? Icons.menu_book_rounded : Icons.laptop_mac_rounded,
                    size: 54,
                    color: AppColors.primary.withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isBook ? 'Reading Verification' : 'Camera Verification',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Position yourself in front of the camera.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // Developer Debug Overlay HUD & Debug Panel:
          // ONLY visible when developer explicitly activates debug mode
          if (_showDebugPanel) ...[
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DEV ML DEBUG: ${isBook ? "BOOK" : "LAPTOP"} (${(visionResult.confidence * 100).toInt()}%)',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _showDebugPanel = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.accent, width: 1),
                            ),
                            child: const Text(
                              'HIDE DEBUG',
                              style: TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildMetricTag(
                          label: 'Person ${visionResult.isPersonDetected ? "✓" : "✗"}',
                          isActive: visionResult.isPersonDetected,
                          confidence: visionResult.personConfidence,
                        ),
                        const SizedBox(width: 6),
                        _buildMetricTag(
                          label: '${isBook ? "Book" : "Laptop"} ${visionResult.isTargetObjectDetected ? "✓" : "✗"}',
                          isActive: visionResult.isTargetObjectDetected,
                          confidence: visionResult.objectConfidence,
                        ),
                        const SizedBox(width: 6),
                        _buildMetricTag(
                          label: 'Activity ${visionResult.isValidWorkingState ? "✓" : "${visionResult.consecutiveValidFrames}/3"}',
                          isActive: visionResult.isValidWorkingState,
                          confidence: visionResult.isValidWorkingState
                              ? 1.0
                              : (visionResult.consecutiveValidFrames / 3.0),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: _buildDevelopmentDebugPanel(visionResult, isBook, provider),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDevelopmentDebugPanel(
    VisionDetectionResult result,
    bool isBook,
    MobListProvider provider,
  ) {
    final timerEngine = provider.timerEngine;
    final isError = result.modelStatus.contains('ERROR') ||
        result.modelStatus.contains('FAILED') ||
        result.conversionStatus == 'ERROR' ||
        result.cameraStatus == 'ERROR';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? AppColors.alarm : AppColors.accent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MOBLIST ML DEBUG PANEL (${result.modelStatus})',
                style: TextStyle(
                  color: isError ? AppColors.alarm : AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Inference: ${result.inferenceTimeMs}ms',
                style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // SECTION 8 SPECIFICATION: Status Indicators
          // Camera: READY / ERROR | Frame: RECEIVED / NOT RECEIVED
          // Image conversion: SUCCESS / ERROR | Model: READY / ERROR
          // Inference: RUNNING / ERROR | Raw detections: <number>
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              _buildDebugStatusTag('Camera', result.cameraStatus, result.cameraStatus == 'READY'),
              _buildDebugStatusTag('Frame', result.frameStatus, result.frameStatus == 'RECEIVED'),
              _buildDebugStatusTag('Conversion', result.conversionStatus, result.conversionStatus == 'SUCCESS'),
              _buildDebugStatusTag('Model', result.modelStatus, result.modelStatus == 'READY'),
              _buildDebugStatusTag('Inference', result.inferenceStatus, result.inferenceStatus == 'RUNNING'),
              Text(
                'Raw detections: ${result.rawDetections.length}',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 8),

          // SECTION 8: Relevant Detections
          // Person Confidence: 0.xx Bounding Box: (...)
          // Laptop Confidence: 0.xx Bounding Box: (...)
          // Book Confidence: 0.xx Bounding Box: (...)
          _buildRelevantDetection(
            'Person',
            result.isPersonDetected,
            result.personConfidence,
            result.personBoundingBox,
          ),
          if (isBook)
            _buildRelevantDetection(
              'Book',
              result.isBookDetected,
              result.bookConfidence,
              result.bookBoundingBox,
            )
          else
            _buildRelevantDetection(
              'Laptop',
              result.isLaptopDetected,
              result.laptopConfidence,
              result.laptopBoundingBox,
            ),

          const Divider(color: Colors.white24, height: 6),

          // SECTION 13 SPECIFICATION: Book / Laptop Validation Diagnostic Status
          if (isBook) ...[
            const Text(
              'BOOK VALIDATION:',
              style: TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.bold),
            ),
            _buildValidationStatusLine('Person detected', result.isPersonDetected ? 'YES' : 'NO', result.isPersonDetected),
            _buildValidationStatusLine('Book detected', result.isBookDetected ? 'YES' : 'NO', result.isBookDetected),
            _buildValidationStatusLine('Spatial relation', result.isSpatialRelationValid ? 'VALID' : 'INVALID', result.isSpatialRelationValid),
            _buildValidationStatusLine('Temporal stability', result.isTemporalStabilityValid ? 'VALID' : 'INVALID', result.isTemporalStabilityValid),
            _buildValidationStatusLine('Final Reading Activity', result.isValidWorkingState ? 'VALID' : 'INVALID', result.isValidWorkingState),
          ] else ...[
            const Text(
              'LAPTOP VALIDATION:',
              style: TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.bold),
            ),
            _buildValidationStatusLine('Person detected', result.isPersonDetected ? 'YES' : 'NO', result.isPersonDetected),
            _buildValidationStatusLine('Laptop detected', result.isLaptopDetected ? 'YES' : 'NO', result.isLaptopDetected),
            _buildValidationStatusLine('Final Working Activity', result.isValidWorkingState ? 'VALID' : 'INVALID', result.isValidWorkingState),
          ],

          // SECTION 8: RAW MODEL OUTPUT before task-specific filtering
          const SizedBox(height: 3),
          Text(
            'RAW MODEL OUTPUT (${result.rawDetections.length} objects detected):',
            style: const TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.bold),
          ),
          if (result.rawDetections.isEmpty)
            const Text('  (Zero objects detected by model)', style: TextStyle(color: Colors.white54, fontSize: 8.5))
          else
            ...result.rawDetections.take(3).map((d) {
              final b = d.boundingBox;
              final boxStr = '[${b.left.toStringAsFixed(2)}, ${b.top.toStringAsFixed(2)}, ${b.width.toStringAsFixed(2)}, ${b.height.toStringAsFixed(2)}]';
              return Text(
                '  • ${d.label.padRight(8)} ${(d.confidence * 100).toInt()}% $boxStr',
                style: TextStyle(
                  color: d.isAccepted ? AppColors.completed : Colors.white70,
                  fontSize: 8.5,
                  fontFamily: 'monospace',
                  fontWeight: d.isAccepted ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }),

          const Divider(color: Colors.white24, height: 6),

          // SECTION 10: Confidence Threshold Selector
          Row(
            children: [
              const Text('Threshold: ', style: TextStyle(color: Colors.white70, fontSize: 9)),
              ...[0.30, 0.40, 0.50, 0.60, 0.70].map((t) {
                final isSelected = (provider.visionDetector.confidenceThreshold - t).abs() < 0.01;
                return GestureDetector(
                  onTap: () => provider.setConfidenceThreshold(t),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accent : Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      t.toStringAsFixed(2),
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
              Text(
                'Valid: ${result.consecutiveValidFrames}/3 | Grace: ${timerEngine.graceSecondsRemaining}s',
                style: TextStyle(
                  color: result.isValidWorkingState ? AppColors.completed : Colors.amberAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDebugStatusTag(String label, String value, bool isSuccess) {
    return Text(
      '$label: $value',
      style: TextStyle(
        color: isSuccess ? AppColors.completed : AppColors.alarm,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildValidationStatusLine(String label, String statusText, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: Colors.white70, fontSize: 8.5),
          ),
          Text(
            statusText,
            style: TextStyle(
              color: isValid ? AppColors.completed : AppColors.alarm,
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelevantDetection(String name, bool isDetected, double confidence, Rect? box) {
    final boxStr = box != null
        ? '[${box.left.toStringAsFixed(2)}, ${box.top.toStringAsFixed(2)}, ${box.width.toStringAsFixed(2)}, ${box.height.toStringAsFixed(2)}]'
        : 'none';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$name: ${isDetected ? "DETECTED" : "NOT DETECTED"}',
            style: TextStyle(
              color: isDetected ? AppColors.completed : Colors.white54,
              fontSize: 8.5,
              fontWeight: isDetected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            'Confidence: ${confidence.toStringAsFixed(2)}  Box: $boxStr',
            style: TextStyle(
              color: isDetected ? Colors.white : Colors.white38,
              fontSize: 8,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTag({
    required String label,
    required bool isActive,
    required double confidence,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.completed.withValues(alpha: 0.2)
              : AppColors.surfaceLight.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.completed : AppColors.surfaceBorder,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.cancel_outlined,
                  color: isActive ? AppColors.completed : AppColors.textMuted,
                  size: 13,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isActive ? AppColors.textPrimary : AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${(confidence * 100).toInt()}%',
              style: TextStyle(
                color: isActive ? AppColors.completed : AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualTimerView(BuildContext context, MobListProvider provider) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 2),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 54, color: AppColors.primary),
            SizedBox(height: 12),
            Text(
              'Manual Focus Task',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'No camera required.\n10 minutes daily target.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws real ML detection bounding boxes over live camera preview:
/// - PERSON: Vibrant Cyan box with label & %
/// - LAPTOP: Vibrant Green box with label & %
/// - BOOK: Vibrant Amber box with label & %
class BoundingBoxPainter extends CustomPainter {
  final List<DetectedItem> detections;
  final bool isFrontCamera;

  BoundingBoxPainter({
    required this.detections,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || size.width == 0 || size.height == 0) return;

    for (final item in detections) {
      if (!item.isAccepted && item.confidence < 0.30) continue;

      final rect = item.boundingBox; // normalized [0.0..1.0]

      // Mirror horizontally if front camera preview is mirrored
      final double left = isFrontCamera
          ? (1.0 - rect.right).clamp(0.0, 1.0) * size.width
          : rect.left.clamp(0.0, 1.0) * size.width;
      final double right = isFrontCamera
          ? (1.0 - rect.left).clamp(0.0, 1.0) * size.width
          : rect.right.clamp(0.0, 1.0) * size.width;
      final double top = rect.top.clamp(0.0, 1.0) * size.height;
      final double bottom = rect.bottom.clamp(0.0, 1.0) * size.height;

      if (right <= left || bottom <= top) continue;

      final scaledRect = Rect.fromLTRB(left, top, right, bottom);
      final isPerson = item.label.toUpperCase() == 'PERSON';
      final isLaptop = item.label.toUpperCase() == 'LAPTOP';
      final isBook = item.label.toUpperCase() == 'BOOK';

      Color boxColor;
      if (isPerson) {
        boxColor = const Color(0xFF00E5FF); // Vibrant Cyan
      } else if (isLaptop) {
        boxColor = const Color(0xFF00E676); // Vibrant Green
      } else if (isBook) {
        boxColor = const Color(0xFFFFB300); // Amber
      } else {
        boxColor = Colors.white60;
      }

      final boxPaint = Paint()
        ..color = boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      // Draw bounding box
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaledRect, const Radius.circular(6)),
        boxPaint,
      );

      // Label + confidence: e.g. PERSON 92%, LAPTOP 87%, BOOK 81%
      final textSpan = TextSpan(
        text: '${item.label.toUpperCase()} ${(item.confidence * 100).toInt()}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeTop = (scaledRect.top - textPainter.height - 6) < 0
          ? scaledRect.top + 4
          : scaledRect.top - textPainter.height - 6;
      final badgeLeft = scaledRect.left;

      final badgeRect = Rect.fromLTWH(
        badgeLeft,
        badgeTop,
        textPainter.width + 8,
        textPainter.height + 4,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
        Paint()..color = boxColor.withValues(alpha: 0.85),
      );

      textPainter.paint(canvas, Offset(badgeLeft + 4, badgeTop + 2));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) => true;
}

