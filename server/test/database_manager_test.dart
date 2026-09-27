import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:server_app/database_manager.dart';

void main() {
  initDatabaseFactory();

  group('إدارة قاعدة البيانات', () {
    late Directory tempDir;
    late Directory dbDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_test_');
      dbDir = Directory('${tempDir.path}/Database');
    });

    tearDown(() async {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('إنشاء ملفات قاعدة البيانات والسكيما', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      expect(File(db.dbFilePath).existsSync(), true);
      expect(File(db.sqlSchemaPath).existsSync(), true);
      final schema = File(db.sqlSchemaPath).readAsStringSync();
      expect(schema, contains('CREATE TABLE IF NOT EXISTS Clients'));
      expect(schema, contains('CREATE TABLE IF NOT EXISTS ChatMessages'));
      expect(schema, contains('CREATE TABLE IF NOT EXISTS ClientSessions'));
      expect(schema, contains('CREATE TABLE IF NOT EXISTS FileTransfers'));
      await db.close();
    });

    test('upsertClient يضيف ثم يحدّث العداد ويحافظ على FirstSeen', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      await db.upsertClient('Ahmed', '127.0.0.1', 5000);
      await db.upsertClient('Ahmed', '192.168.1.5', 6000);

      final clients = await db.queryClients();
      expect(clients.length, 1);
      final row = clients.first;
      expect(row['Username'], 'Ahmed');
      expect(row['TotalConnections'], 2);
      expect(row['IpAddress'], '192.168.1.5');
      expect(row['Port'], 6000);
      expect(row['Status'], 'متصل');
      expect(row['TotalMessagesSent'], 0);
      expect(row['FirstSeen'], isNotNull);
      await db.close();
    });

    test('saveChatMessage يزيد عداد رسائل المرسل ويخزن الجميع للرسائل العامة', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      await db.upsertClient('Ahmed', '127.0.0.1', 5000);
      await db.saveChatMessage('Ahmed', '', 'سلام', false, 'عامة', '127.0.0.1');
      await db.saveChatMessage('Ahmed', 'Sara', 'همسة', true, 'خاصة', '127.0.0.1');

      final messages = await db.queryChatMessages();
      expect(messages.length, 2);
      expect(messages[0]['Recipient'], 'Sara');
      expect(messages[1]['Recipient'], 'الجميع (عامة)');
      expect(messages[0]['IsEncrypted'], 1);

      final clients = await db.queryClients();
      expect(clients.single['TotalMessagesSent'], 2);
      await db.close();
    });

    test('الجلسات: بدء وإنهاء بحساب المدة وإنهاء آخر جلسة نشطة فقط', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      final id1 = await db.startSession('Ahmed', '127.0.0.1', 1);
      final id2 = await db.startSession('Ahmed', '127.0.0.1', 2);
      await db.endSession('Ahmed');

      final sessions = await db.querySessions();
      expect(sessions.length, 2);
      final active = sessions.firstWhere((s) => s['SessionId'] == id2);
      expect(active['SessionState'], 'مكتملة');
      expect(active['DurationSeconds'], isA<int>());
      final other = sessions.firstWhere((s) => s['SessionId'] == id1);
      expect(other['SessionState'], 'نشطة');
      expect(id1, isNot(id2));
      await db.close();
    });

    test('recordBan يحدّث حالة العميل', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      await db.upsertClient('Ahmed', '127.0.0.1', 5000);
      await db.recordBan('Ahmed', 'سبب', 5);

      final clients = await db.queryClients();
      final row = clients.single;
      expect(row['IsBanned'], 1);
      expect(row['BanReason'], 'سبب');
      expect(row['Status'], 'محظور مؤقتاً');
      expect(row['BannedUntil'], isNotNull);
      await db.close();
    });

    test('logFileTransfer يضيف ثم يحدّث الحالة', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      await db.logFileTransfer('t1', 'Ahmed', '', 'a.pdf', 100, 'قيد النقل');
      await db.logFileTransfer('t1', 'Ahmed', '', 'a.pdf', 100, 'مكتمل');

      final files = await db.queryFileTransfers();
      expect(files.length, 1);
      expect(files.single['Status'], 'مكتمل');
      expect(files.single['Recipient'], 'الجميع');
      await db.close();
    });

    test('تثبيتات الإقلاع: العملاء غير متصلين والجلسات المعلقة تُغلق', () async {
      final first = await DatabaseManager.create(dbDirectory: dbDir.path);
      await first.upsertClient('Ahmed', '127.0.0.1', 5000);
      final sessionId = await first.startSession('Ahmed', '127.0.0.1', 5000);
      await first.close();

      final reopened = await DatabaseManager.create(dbDirectory: dbDir.path);
      final clients = await reopened.queryClients();
      expect(clients.single['Status'], 'غير متصل');

      final sessions = await reopened.querySessions();
      final session = sessions.firstWhere((s) => s['SessionId'] == sessionId);
      expect(session['SessionState'], 'منتهية بإغلاق الخادم');
      expect(session['DisconnectedAt'], isNotNull);
      await reopened.close();
    });

    test('استعلامات الإحصاء والتصدير SQL وCSV', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      await db.upsertClient('Ahmed', '127.0.0.1', 5000);
      await db.saveChatMessage('Ahmed', '', 'مرحبا', true, 'عامة', '127.0.0.1');

      final stats = await db.getDatabaseStats();
      expect(stats['clients'], 1);
      expect(stats['messages'], 1);
      expect(stats['dbSize'], greaterThan(0));

      final sqlPath = '${tempDir.path}/dump.sql';
      await db.exportFullDatabaseToSql(sqlPath);
      final sql = File(sqlPath).readAsStringSync();
      expect(sql, contains('INSERT INTO Clients'));
      expect(sql, contains("'مرحبا'"));
      expect(sql, contains('VALUES'));

      final csvPath = '${tempDir.path}/clients.csv';
      await db.exportTableToCsv(
        await db.queryClients(),
        const ['Username', 'IsBanned', 'Status'],
        csvPath,
      );
      final csv = File(csvPath).readAsStringSync();
      expect(csv, contains('"Username"'));
      expect(csv, contains('"Ahmed"'));
      expect(csv, contains('"False"'));
      await db.close();
    });

    test('clearDatabase يفرّغ جميع الجداول', () async {
      final db = await DatabaseManager.create(dbDirectory: dbDir.path);
      await db.upsertClient('Ahmed', '127.0.0.1', 5000);
      await db.saveChatMessage('Ahmed', '', 'x', false, 'عامة', null);
      await db.logFileTransfer('t1', 'Ahmed', '', 'a', 1);
      await db.startSession('Ahmed', '127.0.0.1', 5000);

      await db.clearDatabase();

      const emptyTables = [
        'clients',
        'messages',
        'sessions',
        'dbSize',
      ];
      final stats = await db.getDatabaseStats();
      for (final key in emptyTables) {
        if (key == 'dbSize') continue;
        expect(stats[key], 0, reason: key);
      }
      await db.close();
    });
  });
}