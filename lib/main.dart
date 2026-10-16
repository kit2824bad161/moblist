import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/theme/app_theme.dart';
import 'providers/moblist_provider.dart';
import 'screens/home_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite:
  // On desktop / test environments, use sqflite_common_ffi
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final mobListProvider = MobListProvider();

  // Mount UI immediately so the user never sees an open-and-close crash
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: mobListProvider),
      ],
      child: const MobListApp(),
    ),
  );

  // Initialize provider and database data asynchronously
  try {
    await mobListProvider.initialize();
  } catch (e, stack) {
    debugPrint('[main] Error initializing MobListProvider: $e\n$stack');
  }
}

class MobListApp extends StatelessWidget {
  const MobListApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MobList',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeDashboardScreen(),
    );
  }
}
