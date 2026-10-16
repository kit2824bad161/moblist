import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/constants/app_constants.dart';
import '../models/task_model.dart';
import '../models/daily_task_record_model.dart';
import '../models/productive_session_model.dart';
import '../models/emergency_record_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('moblist.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE daily_task_records ADD COLUMN accumulated_productive_ms INTEGER NOT NULL DEFAULT 0');
          } catch (e) {
            debugPrint('[DatabaseHelper] info adding accumulated_productive_ms: $e');
          }
          try {
            await db.execute('ALTER TABLE daily_task_records ADD COLUMN productive_started_at TEXT');
          } catch (e) {
            debugPrint('[DatabaseHelper] info adding productive_started_at: $e');
          }
          try {
            await db.execute('ALTER TABLE daily_task_records ADD COLUMN last_valid_activity_at TEXT');
          } catch (e) {
            debugPrint('[DatabaseHelper] info adding last_valid_activity_at: $e');
          }
          try {
            await db.execute("ALTER TABLE daily_task_records ADD COLUMN timer_state TEXT NOT NULL DEFAULT 'idle'");
          } catch (e) {
            debugPrint('[DatabaseHelper] info adding timer_state: $e');
          }
          try {
            await db.execute('UPDATE daily_task_records SET accumulated_productive_ms = accumulated_seconds * 1000 WHERE accumulated_productive_ms = 0 AND accumulated_seconds > 0');
          } catch (e) {
            debugPrint('[DatabaseHelper] info updating accumulated_productive_ms: $e');
          }
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        task_type TEXT NOT NULL,
        is_default INTEGER NOT NULL,
        icon_name TEXT NOT NULL,
        target_seconds INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_task_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        task_id TEXT NOT NULL,
        accumulated_seconds INTEGER NOT NULL DEFAULT 0,
        accumulated_productive_ms INTEGER NOT NULL DEFAULT 0,
        productive_started_at TEXT,
        last_valid_activity_at TEXT,
        timer_state TEXT NOT NULL DEFAULT 'idle',
        is_completed INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT,
        UNIQUE(date, task_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE productive_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id TEXT NOT NULL,
        date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        productive_seconds INTEGER NOT NULL,
        session_type TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE emergency_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        year_month TEXT NOT NULL,
        activated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Seed default tasks
    await _seedDefaultTasks(db);
  }

  Future<void> _seedDefaultTasks(Database db) async {
    final defaultTasks = [
      TaskModel(
        id: AppConstants.defaultTaskIdReadBook,
        name: 'Read Book',
        taskType: AppConstants.taskTypeCamera,
        isDefault: true,
        iconName: 'book',
        targetSeconds: AppConstants.dailyTargetSeconds,
        createdAt: DateTime.now(),
      ),
      TaskModel(
        id: AppConstants.defaultTaskIdLeetCode,
        name: 'LeetCode',
        taskType: AppConstants.taskTypeCamera,
        isDefault: true,
        iconName: 'code',
        targetSeconds: AppConstants.dailyTargetSeconds,
        createdAt: DateTime.now(),
      ),
      TaskModel(
        id: AppConstants.defaultTaskIdMyProject,
        name: 'My Project',
        taskType: AppConstants.taskTypeCamera,
        isDefault: true,
        iconName: 'laptop',
        targetSeconds: AppConstants.dailyTargetSeconds,
        createdAt: DateTime.now(),
      ),
      TaskModel(
        id: AppConstants.defaultTaskIdSpeakIt,
        name: 'SpeakIt',
        taskType: AppConstants.taskTypeCamera,
        isDefault: true,
        iconName: 'mic',
        targetSeconds: AppConstants.dailyTargetSeconds,
        createdAt: DateTime.now(),
      ),
    ];

    for (final task in defaultTasks) {
      await db.insert('tasks', task.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // Task Operations
  Future<List<TaskModel>> getAllTasks() async {
    final db = await instance.database;
    final maps = await db.query('tasks', orderBy: 'is_default DESC, created_at ASC');
    return maps.map((m) => TaskModel.fromMap(m)).toList();
  }

  Future<TaskModel?> getTaskById(String id) async {
    final db = await instance.database;
    final maps = await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isNotEmpty) {
      return TaskModel.fromMap(maps.first);
    }
    return null;
  }

  Future<void> insertTask(TaskModel task) async {
    final db = await instance.database;
    await db.insert('tasks', task.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Daily Task Records Operations
  Future<List<DailyTaskRecordModel>> getDailyTaskRecords(String date) async {
    final db = await instance.database;
    final tasks = await getAllTasks();
    final taskMap = {for (final t in tasks) t.id: t};

    final maps = await db.query('daily_task_records', where: 'date = ?', whereArgs: [date]);
    final records = <DailyTaskRecordModel>[];

    for (final m in maps) {
      final taskId = m['task_id'] as String;
      records.add(DailyTaskRecordModel.fromMap(m, task: taskMap[taskId]));
    }

    // Ensure all existing tasks have a record for this date
    for (final task in tasks) {
      final exists = records.any((r) => r.taskId == task.id);
      if (!exists) {
        final newRecord = DailyTaskRecordModel(
          date: date,
          taskId: task.id,
          accumulatedSeconds: 0,
          accumulatedProductiveMs: 0,
          timerState: 'idle',
          isCompleted: false,
          task: task,
        );
        final id = await db.insert('daily_task_records', newRecord.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        records.add(newRecord.copyWith(id: id));
      }
    }

    // Sort: default tasks first, then by task name
    records.sort((a, b) {
      final aDefault = a.task?.isDefault ?? false;
      final bDefault = b.task?.isDefault ?? false;
      if (aDefault && !bDefault) return -1;
      if (!aDefault && bDefault) return 1;
      return (a.task?.name ?? '').compareTo(b.task?.name ?? '');
    });

    return records;
  }

  Future<DailyTaskRecordModel?> getDailyTaskRecord(String date, String taskId) async {
    final db = await instance.database;
    final maps = await db.query('daily_task_records',
        where: 'date = ? AND task_id = ?', whereArgs: [date, taskId], limit: 1);
    if (maps.isNotEmpty) {
      final task = await getTaskById(taskId);
      return DailyTaskRecordModel.fromMap(maps.first, task: task);
    }
    return null;
  }

  Future<void> updateDailyTaskRecord(DailyTaskRecordModel record) async {
    final db = await instance.database;
    await db.update(
      'daily_task_records',
      record.toMap(),
      where: 'date = ? AND task_id = ?',
      whereArgs: [record.date, record.taskId],
    );
  }

  // Productive Session Operations
  Future<int> insertProductiveSession(ProductiveSessionModel session) async {
    final db = await instance.database;
    return await db.insert('productive_sessions', session.toMap());
  }

  Future<List<ProductiveSessionModel>> getSessionsForDate(String date) async {
    final db = await instance.database;
    final maps = await db.query('productive_sessions',
        where: 'date = ?', whereArgs: [date], orderBy: 'start_time DESC');
    return maps.map((m) => ProductiveSessionModel.fromMap(m)).toList();
  }

  // Emergency Records Operations
  Future<bool> isEmergencyDay(String date) async {
    final db = await instance.database;
    final maps = await db.query('emergency_records',
        where: 'date = ?', whereArgs: [date], limit: 1);
    return maps.isNotEmpty;
  }

  Future<int> getEmergencyDaysUsedInMonth(String yearMonth) async {
    final db = await instance.database;
    final maps = await db.query('emergency_records',
        where: 'year_month = ?', whereArgs: [yearMonth]);
    return maps.length;
  }

  Future<bool> activateEmergencyDay(String date, String yearMonth) async {
    final db = await instance.database;
    // Check if already activated
    if (await isEmergencyDay(date)) return true;

    // Check monthly limit (5 days)
    final used = await getEmergencyDaysUsedInMonth(yearMonth);
    if (used >= AppConstants.monthlyEmergencyDaysLimit) {
      return false; // Monthly limit reached!
    }

    final record = EmergencyRecordModel(
      date: date,
      yearMonth: yearMonth,
      activatedAt: DateTime.now(),
    );
    await db.insert('emergency_records', record.toMap());
    return true;
  }

  // History & Summary Operations
  Future<List<String>> getAllRecordedDates() async {
    final db = await instance.database;
    final maps = await db.rawQuery(
        'SELECT DISTINCT date FROM daily_task_records ORDER BY date DESC');
    return maps.map((m) => m['date'] as String).toList();
  }

  // Settings
  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final maps = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isNotEmpty) return maps.first['value'] as String;
    return null;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
