import 'package:flutter/material.dart';

import 'admin_page.dart';
import 'database_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initDatabaseFactory();
  final db = await DatabaseManager.create();
  runApp(ServerAdminApp(db: db));
}

class ServerAdminApp extends StatelessWidget {
  const ServerAdminApp({super.key, required this.db});

  final DatabaseManager db;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام إدارة الشبكة العامة - وحدة التحكم الرئيسية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2C3E50)),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: AdminPage(db: db),
    );
  }
}