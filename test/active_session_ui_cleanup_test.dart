import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moblist/core/constants/app_constants.dart';
import 'package:moblist/models/daily_task_record_model.dart';
import 'package:moblist/models/task_model.dart';
import 'package:moblist/models/vision_state.dart';
import 'package:moblist/providers/moblist_provider.dart';
import 'package:moblist/screens/active_session_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ActiveSessionScreen UI Cleanup & Developer Debug Mode Tests', () {
    late MobListProvider provider;
    late DailyTaskRecordModel record;

    setUp(() {
      provider = MobListProvider();
      final task = TaskModel(
        id: AppConstants.defaultTaskIdLeetCode,
        name: 'LeetCode',
        taskType: AppConstants.taskTypeCamera,
        isDefault: true,
        iconName: 'code',
        targetSeconds: 600,
        createdAt: DateTime.now(),
      );
      record = DailyTaskRecordModel(
        date: '2026-09-29',
        taskId: task.id,
        accumulatedSeconds: 30, // 00:30
        isCompleted: false,
        task: task,
      );
    });

    testWidgets('Normal User UI: Debug panel, threshold buttons, and raw ML info are HIDDEN',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MobListProvider>.value(
          value: provider,
          child: MaterialApp(
            home: ActiveSessionScreen(record: record),
          ),
        ),
      );

      await tester.pump();

      // Normal UI Elements are visible
      expect(find.text('LeetCode'), findsOneWidget);
      expect(find.text('STOP CAMERA'), findsOneWidget);
      expect(find.text('00:30 / 10:00'), findsOneWidget);
      expect(find.text('570 seconds remaining today'), findsOneWidget);

      // Debug UI Elements are NOT visible in normal mode
      expect(find.textContaining('MOBLIST ML DEBUG PANEL'), findsNothing);
      expect(find.textContaining('DEV ML DEBUG'), findsNothing);
      expect(find.text('HIDE DEBUG'), findsNothing);
      expect(find.text('0.30'), findsNothing);
      expect(find.text('0.40'), findsNothing);
      expect(find.text('0.50'), findsNothing);
      expect(find.text('0.60'), findsNothing);
      expect(find.text('0.70'), findsNothing);
    });

    testWidgets('Developer Mode: Long pressing title toggles debug panel ON and OFF',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MobListProvider>.value(
          value: provider,
          child: MaterialApp(
            home: ActiveSessionScreen(record: record),
          ),
        ),
      );

      await tester.pump();

      // Initially hidden
      expect(find.textContaining('MOBLIST ML DEBUG PANEL'), findsNothing);
      expect(find.text('0.50'), findsNothing);

      // Long press on title to toggle developer debug mode ON
      await tester.longPress(find.text('LeetCode'));
      await tester.pump();

      // Now developer debug mode is active
      expect(find.textContaining('MOBLIST ML DEBUG PANEL'), findsOneWidget);
      expect(find.text('0.30'), findsOneWidget);
      expect(find.text('0.40'), findsOneWidget);
      expect(find.text('0.50'), findsOneWidget);
      expect(find.text('0.60'), findsOneWidget);
      expect(find.text('0.70'), findsOneWidget);
      expect(find.text('HIDE DEBUG'), findsOneWidget);

      // Tap HIDE DEBUG to turn it OFF
      await tester.tap(find.text('HIDE DEBUG'));
      await tester.pump();

      // Now hidden again
      expect(find.textContaining('MOBLIST ML DEBUG PANEL'), findsNothing);
      expect(find.text('0.50'), findsNothing);
    });

    testWidgets('Verification Status: Uses clean, user-friendly language for each state',
        (WidgetTester tester) async {
      // Set productive state
      provider.timerEngine.onVisionResult(
        VisionDetectionResult(
          statusDescription: 'Normal Laptop Work',
          isPersonDetected: true,
          isTargetObjectDetected: true,
          isLaptopDetected: true,
          consecutiveValidFrames: 3,
          isValidWorkingState: true,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<MobListProvider>.value(
          value: provider,
          child: MaterialApp(
            home: ActiveSessionScreen(record: record),
          ),
        ),
      );

      await tester.pump();

      // Verifies clean friendly text
      expect(find.text('Activity verified'), findsOneWidget);
      expect(find.text('You can continue working.'), findsOneWidget);
    });
  });
}
