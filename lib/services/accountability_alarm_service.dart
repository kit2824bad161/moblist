import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AccountabilityAlarmService extends ChangeNotifier {
  static final AccountabilityAlarmService instance = AccountabilityAlarmService._init();

  AccountabilityAlarmService._init();

  AudioPlayer? _audioPlayer;
  FlutterLocalNotificationsPlugin? _notificationsPlugin;

  bool _isAlarmActive = false;
  bool _isTemporarilySilenced = false;
  bool _isSoundPlaying = false;
  List<String> _incompleteTasks = [];
  Timer? _scheduleCheckerTimer;

  // Configurable accountability reminder time (default 11:00 PM)
  int _alarmHour = 23;
  int _alarmMinute = 0;

  bool get isAlarmActive => _isAlarmActive;
  bool get isTemporarilySilenced => _isTemporarilySilenced;
  bool get isSoundPlaying => _isSoundPlaying;
  List<String> get incompleteTasks => _incompleteTasks;
  int get alarmHour => _alarmHour;
  int get alarmMinute => _alarmMinute;

  /// Returns user-friendly formatted alarm time string (e.g. "11:00 PM", "09:30 PM")
  String get formattedAlarmTime {
    final int displayHour = _alarmHour % 12 == 0 ? 12 : _alarmHour % 12;
    final String period = _alarmHour >= 12 ? 'PM' : 'AM';
    final String minuteStr = _alarmMinute.toString().padLeft(2, '0');
    return '$displayHour:$minuteStr $period';
  }

  void configureAlarmTime(int hour, int minute) {
    _alarmHour = hour.clamp(0, 23);
    _alarmMinute = minute.clamp(0, 59);
    notifyListeners();
  }

  /// Checks if given timestamp is at or past the configured alarm time
  bool isTimeForAlarm(DateTime now) {
    if (now.hour > _alarmHour) return true;
    if (now.hour == _alarmHour && now.minute >= _alarmMinute) return true;
    return false;
  }

  Future<void> initialize() async {
    try {
      _notificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _notificationsPlugin?.initialize(settings: initSettings);
    } catch (e) {
      debugPrint('Notification init error: $e');
    }

    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer?.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('Audio player init: $e');
    }

    // Start periodic check every 30 seconds for 11 PM alarm trigger
    _scheduleCheckerTimer?.cancel();
    _scheduleCheckerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      notifyListeners();
    });
  }

  /// Triggers the 11 PM accountability alarm
  Future<void> triggerAlarm(List<String> incompleteTasks, {bool userIsInForeground = false}) async {
    _incompleteTasks = incompleteTasks;
    _isAlarmActive = true;

    if (userIsInForeground) {
      // User is currently in the app: silence sound immediately
      _isTemporarilySilenced = true;
      _stopAudio();
    } else {
      // User is outside the app: activate sound and notification
      _isTemporarilySilenced = false;
      await _startAudio();
      await _showAlarmNotification();
    }
    notifyListeners();
  }

  /// Called when user opens or enters MobList Home/Dashboard
  Future<void> onAppForegrounded() async {
    if (_isAlarmActive) {
      _isTemporarilySilenced = true;
      await _stopAudio();
      notifyListeners();
    }
  }

  /// Called when user leaves the app (backgrounded or minimized)
  Future<void> onAppBackgrounded() async {
    if (_isAlarmActive && _incompleteTasks.isNotEmpty) {
      // User left without completing! Alarm becomes active again!
      _isTemporarilySilenced = false;
      await _startAudio();
      await _showAlarmNotification();
      notifyListeners();
    }
  }

  /// Called when all required tasks are completed
  Future<void> dismissPermanently() async {
    _isAlarmActive = false;
    _isTemporarilySilenced = false;
    _incompleteTasks.clear();
    await _stopAudio();
    await _clearNotification();
    notifyListeners();
  }

  Future<void> _startAudio() async {
    if (_isSoundPlaying) return;
    try {
      _isSoundPlaying = true;
      // Play alarm tone
      await _audioPlayer?.play(
        UrlSource('https://actions.google.com/sounds/v1/alarms/alarm_clock.ogg'),
      );
    } catch (e) {
      debugPrint('Error playing alarm audio: $e');
      _isSoundPlaying = false;
    }
  }

  Future<void> _stopAudio() async {
    try {
      _isSoundPlaying = false;
      await _audioPlayer?.stop();
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  Future<void> _showAlarmNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'accountability_alarm_channel',
      'Accountability Alarm',
      channelDescription: 'Alarms for incomplete required daily tasks at 11 PM',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      playSound: true,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    final taskListStr = _incompleteTasks.join(', ');
    try {
      await _notificationsPlugin?.show(
        id: 1100,
        title: '⚠️ MobList: Accountability Alarm!',
        body: 'Required tasks incomplete: $taskListStr. Open MobList to finish!',
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing alarm notification: $e');
    }
  }

  Future<void> _clearNotification() async {
    try {
      await _notificationsPlugin?.cancel(id: 1100);
    } catch (e) {
      debugPrint('Error clearing notification: $e');
    }
  }

  @override
  void dispose() {
    _scheduleCheckerTimer?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }
}
