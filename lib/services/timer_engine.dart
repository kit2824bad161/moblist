import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/vision_state.dart';

typedef PersistTimerStateCallback = void Function({
  required String taskId,
  required String date,
  required int accumulatedMs,
  required DateTime? productiveStartedAt,
  required DateTime? lastValidActivityAt,
  required ProductiveState state,
  required bool isCompleted,
});

class TimerEngine extends ChangeNotifier {
  ProductiveState _state = ProductiveState.idle;

  String _taskId = '';
  String _date = '';

  // Exact millisecond accounting: source of truth for accumulated productive time
  int _accumulatedProductiveMs = 0;
  DateTime? _productiveBurstStart;
  DateTime? _lastValidActivityAt;

  // Timestamp accounting for grace period
  DateTime? _gracePeriodStart;
  int _graceSecondsRemaining = AppConstants.gracePeriodSeconds;

  String _errorMessage = '';
  VisionDetectionResult _lastVisionResult = VisionDetectionResult.initial();
  Timer? _displayTicker;

  // Temporal validation counters
  int _consecutiveValidDetections = 0;
  int _consecutiveInvalidDetections = 0;
  static const int _requiredValidForProductive = 3;
  static const int _requiredInvalidForGrace = 2;

  // Callbacks
  VoidCallback? onTargetReached;
  Function(int totalSeconds)? onSecondsUpdated;
  Function(ProductiveState newState)? onStateChanged;
  PersistTimerStateCallback? onPersistTimerState;

  // Getters
  ProductiveState get state => _state;
  String get taskId => _taskId;
  String get date => _date;
  int get accumulatedProductiveMs => _accumulatedProductiveMs;
  DateTime? get productiveBurstStart => _productiveBurstStart;
  DateTime? get lastValidActivityAt => _lastValidActivityAt;
  int get graceSecondsRemaining => _graceSecondsRemaining;
  VisionDetectionResult get lastVisionResult => _lastVisionResult;
  String get errorMessage => _errorMessage;
  int get consecutiveValidDetections => _consecutiveValidDetections;

  /// Total integer seconds for backward compatibility with tests
  int get previouslyAccumulatedSeconds => _accumulatedProductiveMs ~/ 1000;

  /// Exact total productive milliseconds accumulated so far based on timestamps
  int get totalProductiveMs {
    int currentBurstMs = 0;
    if (_state == ProductiveState.productive && _productiveBurstStart != null) {
      currentBurstMs = max(0, DateTime.now().difference(_productiveBurstStart!).inMilliseconds);
    }
    return _accumulatedProductiveMs + currentBurstMs;
  }

  /// Total integer seconds for display and persistence (derived strictly from timestamps)
  int get totalAccumulatedSeconds => totalProductiveMs ~/ 1000;

  /// Current session productive seconds (derived from timestamps)
  int get currentSessionProductiveSeconds => totalProductiveMs ~/ 1000;

  bool get isCompleted => totalProductiveMs >= AppConstants.dailyTargetSeconds * 1000;
  bool get isSessionActivelyProductive => _state == ProductiveState.productive;

  /// Returns mm:ss formatted string of total accumulated productive time
  String get formattedProductiveTime {
    final minutes = totalAccumulatedSeconds ~/ 60;
    final seconds = totalAccumulatedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void pauseSession() => pauseManualSession();

  void initialize({
    String taskId = '',
    String date = '',
    int initialAccumulatedSeconds = 0,
    int initialAccumulatedMs = 0,
    DateTime? initialStartedAt,
    DateTime? initialLastValidAt,
    ProductiveState initialState = ProductiveState.idle,
    VoidCallback? onTargetReachedCallback,
    Function(int totalSeconds)? onSecondsUpdatedCallback,
    Function(ProductiveState newState)? onStateChangedCallback,
    PersistTimerStateCallback? onPersistTimerStateCallback,
  }) {
    _taskId = taskId;
    _date = date;
    // Prefer explicit ms, otherwise fall back to seconds * 1000
    _accumulatedProductiveMs = initialAccumulatedMs > 0
        ? initialAccumulatedMs
        : (initialAccumulatedSeconds * 1000);
    _productiveBurstStart = initialStartedAt;
    _lastValidActivityAt = initialLastValidAt;
    _gracePeriodStart = null;
    _graceSecondsRemaining = AppConstants.gracePeriodSeconds;
    _consecutiveValidDetections = 0;
    _consecutiveInvalidDetections = 0;
    _state = initialState;
    _errorMessage = '';
    _lastVisionResult = VisionDetectionResult.initial();

    onTargetReached = onTargetReachedCallback;
    onSecondsUpdated = onSecondsUpdatedCallback;
    onStateChanged = onStateChangedCallback;
    onPersistTimerState = onPersistTimerStateCallback;

    _startDisplayTicker();
    notifyListeners();
  }

  void _startDisplayTicker() {
    _displayTicker?.cancel();
    // UI refresh ticker solely for updating time display (every 250ms)
    // Does NOT increment time; time is computed strictly via DateTime.now() difference!
    _displayTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _evaluateTimeAndTransitions();
    });
  }

  void _evaluateTimeAndTransitions() {
    final now = DateTime.now();

    if (_state == ProductiveState.productive) {
      final currentTotalSecs = totalAccumulatedSeconds;
      onSecondsUpdated?.call(currentTotalSecs);
      notifyListeners();

      // Check cumulative 10-minute completion (>= 600,000 ms = 600s)
      if (totalProductiveMs >= AppConstants.dailyTargetSeconds * 1000) {
        _commitCurrentBurst(now);
        _transitionTo(ProductiveState.completed);
        onTargetReached?.call();
        _triggerPersist();
        return;
      }
    } else if (_state == ProductiveState.gracePeriod) {
      if (_gracePeriodStart != null) {
        final elapsedGraceMs = now.difference(_gracePeriodStart!).inMilliseconds;
        _graceSecondsRemaining = max(0, AppConstants.gracePeriodSeconds - (elapsedGraceMs ~/ 1000));

        // When 30 seconds elapse without valid activity, transition to PAUSED
        if (elapsedGraceMs >= AppConstants.gracePeriodSeconds * 1000) {
          _gracePeriodStart = null;
          _graceSecondsRemaining = 0;
          _transitionTo(ProductiveState.paused);
          _triggerPersist();
        }
        notifyListeners();
      }
    }
  }

  /// Called when camera task begins opening
  void startCameraSession() {
    _transitionTo(ProductiveState.cameraStarting);
    _triggerPersist();
  }

  /// Called when camera preview is active and frames are being processed
  void cameraReady() {
    _consecutiveValidDetections = 0;
    _consecutiveInvalidDetections = 0;
    _transitionTo(ProductiveState.verifying);
    _triggerPersist();
  }

  /// Updates ML vision result with temporal validation filter
  void updateVisionResult(VisionDetectionResult result) {
    _lastVisionResult = result;

    if (_state == ProductiveState.completed ||
        _state == ProductiveState.cameraStopped ||
        _state == ProductiveState.idle) {
      return;
    }

    final now = DateTime.now();
    final isCandidateValid =
        (result.isPersonDetected && result.isTargetObjectDetected) || result.isValidWorkingState;

    if (isCandidateValid) {
      _consecutiveValidDetections++;
      _consecutiveInvalidDetections = 0;
      _lastValidActivityAt = now;

      // Require 3 consecutive valid frames before starting/resuming productive timer
      if (_consecutiveValidDetections >= _requiredValidForProductive || result.isValidWorkingState) {
        if (_state == ProductiveState.verifying ||
            _state == ProductiveState.paused ||
            _state == ProductiveState.gracePeriod) {
          // Valid detection verified! Start productive burst from now
          _productiveBurstStart = now;
          _gracePeriodStart = null;
          _graceSecondsRemaining = AppConstants.gracePeriodSeconds;
          _transitionTo(ProductiveState.productive);
          _triggerPersist();
        }
      }
    } else {
      _consecutiveInvalidDetections++;
      _consecutiveValidDetections = 0;

      // If in productive state, require 2 consecutive invalid frames before dropping to grace period
      if (_state == ProductiveState.productive &&
          _consecutiveInvalidDetections >= _requiredInvalidForGrace) {
        // Commit valid productive time accumulated up to this exact millisecond
        _commitCurrentBurst(now);

        // Start 30-second grace period (does NOT add unverified time)
        _gracePeriodStart = now;
        _graceSecondsRemaining = AppConstants.gracePeriodSeconds;
        _transitionTo(ProductiveState.gracePeriod);
        _triggerPersist();
      }
    }

    notifyListeners();
  }

  void _commitCurrentBurst(DateTime now) {
    if (_productiveBurstStart != null) {
      _accumulatedProductiveMs += max(0, now.difference(_productiveBurstStart!).inMilliseconds);
      _productiveBurstStart = null;
    }
  }

  /// For Type B manual tasks (no camera/ML)
  void startManualSession() {
    final now = DateTime.now();
    _productiveBurstStart = now;
    _lastValidActivityAt = now;
    _transitionTo(ProductiveState.productive);
    _triggerPersist();
    notifyListeners();
  }

  void pauseManualSession() {
    _commitCurrentBurst(DateTime.now());
    _transitionTo(ProductiveState.paused);
    _triggerPersist();
    notifyListeners();
  }

  /// User manually presses "STOP CAMERA" or navigates away
  void stopSessionManually() {
    _commitCurrentBurst(DateTime.now());
    _transitionTo(ProductiveState.cameraStopped);
    _triggerPersist();
    notifyListeners();
  }

  void setError(String message) {
    _errorMessage = message;
    _commitCurrentBurst(DateTime.now());
    _transitionTo(ProductiveState.error);
    _triggerPersist();
    notifyListeners();
  }

  void _transitionTo(ProductiveState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
    notifyListeners();
  }

  void _triggerPersist() {
    if (_taskId.isNotEmpty && _date.isNotEmpty) {
      onPersistTimerState?.call(
        taskId: _taskId,
        date: _date,
        accumulatedMs: totalProductiveMs,
        productiveStartedAt: _productiveBurstStart,
        lastValidActivityAt: _lastValidActivityAt,
        state: _state,
        isCompleted: isCompleted,
      );
    }
  }

  @override
  void dispose() {
    _displayTicker?.cancel();
    super.dispose();
  }
}

