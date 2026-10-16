import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moblist/core/constants/app_constants.dart';
import 'package:moblist/models/daily_task_record_model.dart';
import 'package:moblist/models/task_model.dart';
import 'package:moblist/widgets/task_card.dart';

void main() {
  testWidgets('TaskCard renders correctly and triggers start callback', (WidgetTester tester) async {
    final task = TaskModel(
      id: AppConstants.defaultTaskIdReadBook,
      name: 'Read Book',
      taskType: AppConstants.taskTypeCamera,
      isDefault: true,
      iconName: 'book',
      targetSeconds: 600,
      createdAt: DateTime.now(),
    );

    final record = DailyTaskRecordModel(
      date: '2026-09-26',
      taskId: task.id,
      accumulatedSeconds: 455, // 07:35
      isCompleted: false,
      task: task,
    );

    bool started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(
            record: record,
            onStart: () {
              started = true;
            },
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify task title and formatted progress
    expect(find.text('Read Book'), findsOneWidget);
    expect(find.text('07:35 / 10:00'), findsOneWidget);
    expect(find.text('Camera + ML'), findsOneWidget);
    expect(find.text('RESUME TASK'), findsOneWidget);

    // Tap action button
    await tester.tap(find.text('RESUME TASK'));
    await tester.pump();
    expect(started, isTrue);
  });
}
