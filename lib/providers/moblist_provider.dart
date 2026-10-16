import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';
import '../database/database_helper.dart';
import '../models/task_model.dart';
import '../models/daily_task_record_model.dart';
import '../models/productive_session_model.dart';
import '../models/daily_summary_model.dart';
import '../models/vision_state.dart';
import '../ml/ml_vision_detector.dart';
import '../camera/camera_service.dart';
import '../services/timer_engine.dart';
import '../services/accountability_alarm_service.dart';

class MobListProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final CameraService _cameraService = CameraService();
  final MLVisionDetector _visionDetector = MLVisionDetector();
  final TimerEngine _timerEngine = TimerEngine();
  final AccountabilityAlarmService _alarmService = AccountabilityAlarmService.instance;

  // Today state
  String _todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  List<DailyTaskRecordModel> _todayRecords = [];
  bool _isTodayEmergency = false;
  int _emergencyDaysUsedThisMonth = 0;
  bool _isLoading = true;

  // Active Session state
  DailyTaskRecordModel? _activeRecord;
  DateTime? _activeSessionStart;
  bool _isCameraActive = false;

  bool _isProcessingFrame = false;
  int _framesReceived = 0;
  int _framesSkipped = 0;
  Timer? _alarmCheckTimer;

  // Getters
  String get todayDate => _todayDate;
  List<DailyTaskRecordModel> get todayRecords => _todayRecords;
  bool get isTodayEmergency => _isTodayEmergency;
  int get emergencyDaysUsedThisMonth => _emergencyDaysUsedThisMonth;
  int get emergencyDaysRemainingThisMonth =>
      (AppConstants.monthlyEmergencyDaysLimit - _emergencyDaysUsedThisMonth).clamp(0, 5);

  bool get isLoading => _isLoading;
  DailyTaskRecordModel? get activeRecord => _activeRecord;
  TimerEngine get timerEngine => _timerEngine;
  CameraService get cameraService => _cameraService;
  MLVisionDetector get visionDetector => _visionDetector;
  AccountabilityAlarmService get alarmService => _alarmService;
  bool get isCameraActive => _isCameraActive;

  // Configurable Daily Accountability Alarm getters
  TimeOfDay get configuredAlarmTime => TimeOfDay(
        hour: _alarmService.alarmHour,
        minute: _alarmService.alarmMinute,
      );
  String get formattedAlarmTime => _alarmService.formattedAlarmTime;

  // Overall Completion stats
  int get completedRequiredTasksCount =>
      _todayRecords.where((r) => (r.task?.isDefault ?? false) && r.isCompleted).length;

  int get totalRequiredTasksCount =>
      _todayRecords.where((r) => r.task?.isDefault ?? false).length;

  int get totalCompletedTasksCount =>
      _todayRecords.where((r) => r.isCompleted).length;

  int get totalTasksCount => _todayRecords.length;

  int get totalTodayProductiveSeconds =>
      _todayRecords.fold(0, (sum, r) => sum + r.accumulatedSeconds);

  int _lastBroadcastSeconds = -1;

  MobListProvider() {
    WidgetsBinding.instance.addObserver(this);
    // Listen directly to TimerEngine so timer state/tick changes propagate live
    _timerEngine.addListener(() {
      notifyListeners();
    });
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    await _alarmService.initialize();

    // Load persisted accountability alarm time (default 11:00 PM if unset)
    final savedAlarmTime = await _db.getSetting('accountability_alarm_time');
    if (savedAlarmTime != null && savedAlarmTime.contains(':')) {
      final parts = savedAlarmTime.split(':');
      final h = int.tryParse(parts[0]) ?? 23;
      final m = int.tryParse(parts[1]) ?? 0;
      _alarmService.configureAlarmTime(h, m);
    }

    await _loadTodayData();

    // Start accountability alarm check loop (every 15 seconds)
    _alarmCheckTimer?.cancel();
    _alarmCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkAccountabilityAlarm();
    });

    checkAccountabilityAlarm();
    _isLoading = false;
    notifyListeners();
  }

  /// Updates and persists the daily accountability alarm time
  Future<void> updateAlarmTime(TimeOfDay newTime) async {
    _alarmService.configureAlarmTime(newTime.hour, newTime.minute);
    final timeStr =
        '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}';
    await _db.setSetting('accountability_alarm_time', timeStr);
    await checkAccountabilityAlarm();
    notifyListeners();
  }

  Future<void> _loadTodayData() async {
    _todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final currentYearMonth = DateFormat('yyyy-MM').format(DateTime.now());

    _isTodayEmergency = await _db.isEmergencyDay(_todayDate);
    _emergencyDaysUsedThisMonth = await _db.getEmergencyDaysUsedInMonth(currentYearMonth);
    _todayRecords = await _db.getDailyTaskRecords(_todayDate);
    notifyListeners();
  }

  /// Refreshes daily data and checks for midnight date transition
  Future<void> refresh() async {
    final nowFormatted = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (nowFormatted != _todayDate) {
      // New calendar day has arrived!
      _todayDate = nowFormatted;
    }
    await _loadTodayData();
    check11PmAccountabilityAlarm();
  }

  /// Activate Emergency Day for today
  Future<bool> activateEmergencyDay() async {
    final currentYearMonth = DateFormat('yyyy-MM').format(DateTime.now());
    final success = await _db.activateEmergencyDay(_todayDate, currentYearMonth);
    if (success) {
      _isTodayEmergency = true;
      _emergencyDaysUsedThisMonth = await _db.getEmergencyDaysUsedInMonth(currentYearMonth);
      // Excuse tasks and silence alarm permanently for today
      await _alarmService.dismissPermanently();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Add Type B Custom Task
  Future<void> addCustomTask(String name) async {
    if (name.trim().isEmpty) return;

    final newTask = TaskModel(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      taskType: AppConstants.taskTypeManual,
      isDefault: false,
      iconName: 'custom',
      targetSeconds: AppConstants.dailyTargetSeconds,
      createdAt: DateTime.now(),
    );

    await _db.insertTask(newTask);
    await _loadTodayData();
  }

  /// Start a task session
  Future<void> startSession(DailyTaskRecordModel record) async {
    // 1. Always fetch freshest record from todayRecords or database
    final freshRecord = _todayRecords.firstWhere(
      (r) => r.taskId == record.taskId,
      orElse: () => record,
    );

    // If session is already active for this exact task, continue seamlessly
    if (_activeRecord?.taskId == freshRecord.taskId &&
        (_isCameraActive || _timerEngine.state == ProductiveState.productive)) {
      notifyListeners();
      return;
    }

    _activeRecord = freshRecord;
    _activeSessionStart = DateTime.now();

    final accumulatedMs = freshRecord.accumulatedProductiveMs > 0
        ? freshRecord.accumulatedProductiveMs
        : (freshRecord.accumulatedSeconds * 1000);

    _timerEngine.initialize(
      taskId: freshRecord.taskId,
      date: _todayDate,
      initialAccumulatedMs: accumulatedMs,
      initialStartedAt: freshRecord.productiveStartedAt,
      initialLastValidAt: freshRecord.lastValidActivityAt,
      initialState: freshRecord.timerState == 'productive'
          ? ProductiveState.productive
          : ProductiveState.idle,
      onTargetReachedCallback: () {
        _handleTaskCompleted();
      },
      onSecondsUpdatedCallback: (totalSeconds) {
        _handleSecondsUpdated(totalSeconds);
      },
      onStateChangedCallback: (state) {
        notifyListeners();
      },
      onPersistTimerStateCallback: ({
        required String taskId,
        required String date,
        required int accumulatedMs,
        required DateTime? productiveStartedAt,
        required DateTime? lastValidActivityAt,
        required ProductiveState state,
        required bool isCompleted,
      }) {
        _persistTimerState(
          taskId: taskId,
          date: date,
          accumulatedMs: accumulatedMs,
          productiveStartedAt: productiveStartedAt,
          lastValidActivityAt: lastValidActivityAt,
          state: state,
          isCompleted: isCompleted,
        );
      },
    );

    if (freshRecord.task?.isCameraTask ?? false) {
      _isCameraActive = true;
      _visionDetector.initialize();
      _timerEngine.startCameraSession();
      notifyListeners();

      final started = await _cameraService.startCamera(
        onFrame: (CameraImage image) {
          _processCameraFrame(image);
        },
        onError: (err) {
          debugPrint('Camera error: $err');
          _timerEngine.setError(err);
        },
      );

      if (started) {
        _timerEngine.cameraReady();
      } else {
        _timerEngine.setError('Camera access is required. Please grant camera permission.');
      }
    } else {
      // Manual Type B task
      _isCameraActive = false;
      _timerEngine.startManualSession();
    }

    notifyListeners();
  }

  Future<void> _persistTimerState({
    required String taskId,
    required String date,
    required int accumulatedMs,
    required DateTime? productiveStartedAt,
    required DateTime? lastValidActivityAt,
    required ProductiveState state,
    required bool isCompleted,
  }) async {
    final idx = _todayRecords.indexWhere((r) => r.taskId == taskId && r.date == date);
    if (idx != -1) {
      final updated = _todayRecords[idx].copyWith(
        accumulatedSeconds: accumulatedMs ~/ 1000,
        accumulatedProductiveMs: accumulatedMs,
        productiveStartedAt: productiveStartedAt,
        lastValidActivityAt: lastValidActivityAt,
        timerState: state.name,
        isCompleted: isCompleted,
      );
      _todayRecords[idx] = updated;
      await _db.updateDailyTaskRecord(updated);
    }
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (_activeRecord == null || !_isCameraActive) return;
    _framesReceived++;

    if (_isProcessingFrame) {
      _framesSkipped++;
      return; // Skip frame to prevent overlapping inference calls
    }
    _isProcessingFrame = true;

    try {
      final isBook = _activeRecord!.taskId == AppConstants.defaultTaskIdReadBook;
      final result = await _visionDetector.processLiveFrame(
        image: image,
        sensorRotation: _cameraService.sensorOrientation,
        isFrontCamera: _cameraService.isFrontCamera,
        isBookTask: isBook,
        framesReceived: _framesReceived,
        framesSkipped: _framesSkipped,
      );

      // Diagnostic real-time logging
      debugPrint(
        '[ML Pipeline] ${result.timestamp.toIso8601String().substring(11, 23)} | '
        'Camera: ${result.cameraStatus} | '
        'Conversion: ${result.conversionStatus} | '
        'Model: ${result.modelStatus} | '
        'Person: ${result.isPersonDetected} (${(result.personConfidence * 100).toStringAsFixed(1)}%) | '
        'Laptop: ${result.isLaptopDetected} (${(result.laptopConfidence * 100).toStringAsFixed(1)}%) | '
        'Book: ${result.isBookDetected} (${(result.bookConfidence * 100).toStringAsFixed(1)}%) | '
        'Valid: ${result.isValidWorkingState} (${result.consecutiveValidFrames}/3) | '
        'Latency: ${result.inferenceTimeMs}ms | '
        'Raw items: ${result.rawDetections.length}',
      );

      _timerEngine.updateVisionResult(result);
      notifyListeners();
    } catch (e, stack) {
      debugPrint('[MobListProvider] Error processing camera frame: $e\n$stack');
      final errResult = VisionDetectionResult.error('INFERENCE ERROR: $e');
      _timerEngine.updateVisionResult(errResult);
      notifyListeners();
    } finally {
      _isProcessingFrame = false;
    }
  }

  void setConfidenceThreshold(double threshold) {
    _visionDetector.setConfidenceThreshold(threshold);
    notifyListeners();
  }

  void _handleSecondsUpdated(int totalSeconds) {
    if (_activeRecord == null) return;
    final totalMs = _timerEngine.totalProductiveMs;
    // Update local record in list
    final idx = _todayRecords.indexWhere((r) => r.taskId == _activeRecord!.taskId);
    if (idx != -1) {
      _todayRecords[idx] = _todayRecords[idx].copyWith(
        accumulatedSeconds: totalSeconds,
        accumulatedProductiveMs: totalMs,
        productiveStartedAt: _timerEngine.productiveBurstStart,
        lastValidActivityAt: _timerEngine.lastValidActivityAt,
        timerState: _timerEngine.state.name,
        isCompleted: totalMs >= AppConstants.dailyTargetSeconds * 1000,
      );
    }
    // Broadcast live update whenever second increments
    if (_lastBroadcastSeconds != totalSeconds) {
      _lastBroadcastSeconds = totalSeconds;
      notifyListeners();
    }
  }

  /// Automatically called when >= 600s (600,000 ms) reached
  Future<void> _handleTaskCompleted() async {
    if (_activeRecord == null) return;

    final totalMs = _timerEngine.totalProductiveMs;
    final totalSecs = totalMs ~/ 1000;
    final updatedRecord = _activeRecord!.copyWith(
      accumulatedSeconds: totalSecs,
      accumulatedProductiveMs: totalMs,
      productiveStartedAt: null,
      timerState: ProductiveState.completed.name,
      isCompleted: true,
      completedAt: DateTime.now(),
    );

    // Stop camera and release hardware
    await _stopCameraHardware();

    // Persist to database
    await _db.updateDailyTaskRecord(updatedRecord);
    await _saveProductiveSession(totalSecs);

    _activeRecord = updatedRecord;
    await _loadTodayData();

    // Check if all required tasks are finished
    final allRequiredDone = _todayRecords
        .where((r) => (r.task?.isDefault ?? false))
        .every((r) => r.isCompleted);
    if (allRequiredDone) {
      await _alarmService.dismissPermanently();
    }

    notifyListeners();
  }

  /// User presses "STOP CAMERA" manually before reaching 10 minutes or navigates away
  Future<void> stopSessionManually() async {
    if (_activeRecord == null) return;

    _timerEngine.stopSessionManually();
    final totalMs = _timerEngine.totalProductiveMs;
    final totalSecs = totalMs ~/ 1000;

    await _stopCameraHardware();

    final isDone = totalMs >= AppConstants.dailyTargetSeconds * 1000;
    final updatedRecord = _activeRecord!.copyWith(
      accumulatedSeconds: totalSecs,
      accumulatedProductiveMs: totalMs,
      productiveStartedAt: null,
      timerState: isDone ? ProductiveState.completed.name : ProductiveState.paused.name,
      isCompleted: isDone,
      completedAt: isDone ? DateTime.now() : null,
    );

    await _db.updateDailyTaskRecord(updatedRecord);
    await _saveProductiveSession(totalSecs);

    _activeRecord = null;
    await _loadTodayData();
    notifyListeners();
  }

  Future<void> _stopCameraHardware() async {
    _isCameraActive = false;
    await _cameraService.stopCamera();
    _visionDetector.resetTemporalState();
  }

  Future<void> _saveProductiveSession(int currentTotalSeconds) async {
    if (_activeSessionStart == null || _activeRecord == null) return;

    final sessionSeconds = _timerEngine.currentSessionProductiveSeconds;
    if (sessionSeconds > 0) {
      final session = ProductiveSessionModel(
        taskId: _activeRecord!.taskId,
        date: _todayDate,
        startTime: _activeSessionStart!,
        endTime: DateTime.now(),
        productiveSeconds: sessionSeconds,
        sessionType: _activeRecord!.task?.taskType ?? 'CAMERA',
      );
      await _db.insertProductiveSession(session);
    }
  }

  /// Checks the configured daily accountability alarm rule
  Future<void> checkAccountabilityAlarm() async {
    if (_isTodayEmergency) {
      // Day is excused: no alarm
      if (_alarmService.isAlarmActive) {
        await _alarmService.dismissPermanently();
      }
      return;
    }

    final now = DateTime.now();
    // Check against user-configured alarm time
    final isAlarmTime = _alarmService.isTimeForAlarm(now);

    if (isAlarmTime) {
      final incompleteRequired = _todayRecords
          .where((r) => (r.task?.isDefault ?? false) && !r.isCompleted)
          .map((r) => r.task?.name ?? 'Required Task')
          .toList();

      if (incompleteRequired.isNotEmpty) {
        if (!_alarmService.isAlarmActive) {
          // Trigger alarm, silenced because user is in app foreground right now
          await _alarmService.triggerAlarm(incompleteRequired, userIsInForeground: true);
        }
      } else {
        // All required tasks are complete!
        if (_alarmService.isAlarmActive) {
          await _alarmService.dismissPermanently();
        }
      }
    } else {
      // If before alarm time, ensure alarm is not active
      if (_alarmService.isAlarmActive) {
        await _alarmService.dismissPermanently();
      }
    }
  }

  /// Backward compatible alias
  Future<void> check11PmAccountabilityAlarm() => checkAccountabilityAlarm();

  // History & Analytics Queries
  Future<DailySummaryModel> getSummaryForDate(String date) async {
    final records = await _db.getDailyTaskRecords(date);
    final isEmergency = await _db.isEmergencyDay(date);
    final totalSecs = records.fold(0, (sum, r) => sum + r.accumulatedSeconds);
    final completedCount = records.where((r) => r.isCompleted).length;

    return DailySummaryModel(
      date: date,
      totalProductiveSeconds: totalSecs,
      completedTasksCount: completedCount,
      totalTasksCount: records.length,
      isEmergencyDay: isEmergency,
      taskRecords: records,
    );
  }

  Future<List<String>> getAllHistoryDates() async {
    return await _db.getAllRecordedDates();
  }

  // App Lifecycle Handling (Sections 15, 16, 23)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // User entered MobList -> Silence alarm while in app
      _alarmService.onAppForegrounded();
      refresh();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // User left MobList -> If incomplete tasks exist, alarm reactivates!
      _alarmService.onAppBackgrounded();

      // Persist current session progress immediately so no time is ever lost
      if (_activeRecord != null) {
        final totalSecs = _timerEngine.totalAccumulatedSeconds;
        final updatedRecord = _activeRecord!.copyWith(
          accumulatedSeconds: totalSecs,
          isCompleted: totalSecs >= AppConstants.dailyTargetSeconds,
        );
        _db.updateDailyTaskRecord(updatedRecord);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmCheckTimer?.cancel();
    _stopCameraHardware();
    _timerEngine.dispose();
    _visionDetector.dispose();
    super.dispose();
  }
}
