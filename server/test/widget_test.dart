import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:server_app/database_manager.dart';
import 'package:server_app/main.dart';

void main() {
  testWidgets('لوحة الإدارة الرئيسية تظهر عناصرها الأساسية', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late DatabaseManager db;
    late Directory tempDir;

    await tester.runAsync(() async {
      initDatabaseFactory();
      tempDir = await Directory.systemTemp.createTemp('server_app_test_');
      db = await DatabaseManager.create(dbDirectory: tempDir.path);
    });

    await tester.pumpWidget(ServerAdminApp(db: db));
    await tester.pump();

    expect(find.text('إدارة الخادم - نظام تبادل البيانات (Server)'),
        findsOneWidget);
    expect(find.text('الخادم متوقف'), findsOneWidget);
    expect(find.text('تشغيل الخادم'), findsOneWidget);
    expect(find.text('الحالة: الخادم غير مشغل'), findsOneWidget);

    await tester.runAsync(() async {
      await db.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
  });
}