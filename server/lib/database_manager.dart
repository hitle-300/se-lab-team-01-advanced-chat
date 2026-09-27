import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String formatSqlDate(DateTime? value) {
  if (value == null) return 'NULL';
  String two(int n) => n.toString().padLeft(2, '0');
  return "'${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}'";
}

String escapeSql(Object? value) {
  if (value == null) return '';
  return value.toString().replaceAll("'", "''");
}

void initDatabaseFactory() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

void initDatabaseFactoryNoIsolate() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
}

class DatabaseManager {
  DatabaseManager._(this._db, this.dbDirectory)
      : dbFilePath = p.join(dbDirectory, 'chat_server.db'),
        sqlSchemaPath = p.join(dbDirectory, 'database_schema.sql');

  final Database _db;
  final String dbDirectory;
  final String dbFilePath;
  final String sqlSchemaPath;

  static String defaultDatabaseDirectory() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return p.join(exeDir, 'Database');
    } catch (_) {
      return p.join(Directory.current.path, 'Database');
    }
  }

  static Future<DatabaseManager> create({String? dbDirectory}) async {
    final dir = dbDirectory ?? defaultDatabaseDirectory();
    Directory(dir).createSync(recursive: true);
    final manager = DatabaseManager._(await _openDatabase(p.join(dir, 'chat_server.db')), dir);
    await manager._saveSqlSchemaScript();
    await manager._applyStartupFixups();
    return manager;
  }

  static Future<Database> _openDatabase(String path) async {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE IF NOT EXISTS Clients (
    ClientId INTEGER PRIMARY KEY AUTOINCREMENT,
    Username TEXT NOT NULL UNIQUE,
    IpAddress TEXT,
    Port INTEGER,
    FirstSeen TEXT,
    LastSeen TEXT,
    TotalConnections INTEGER DEFAULT 0,
    TotalMessagesSent INTEGER DEFAULT 0,
    Status TEXT DEFAULT 'غير متصل',
    IsBanned INTEGER DEFAULT 0,
    BanReason TEXT,
    BannedUntil TEXT
)
''');
          await db.execute('''
CREATE TABLE IF NOT EXISTS ChatMessages (
    MessageId INTEGER PRIMARY KEY AUTOINCREMENT,
    Sender TEXT NOT NULL,
    Recipient TEXT,
    MessageType TEXT,
    MessageContent TEXT,
    IsEncrypted INTEGER DEFAULT 0,
    Timestamp TEXT,
    SenderIp TEXT
)
''');
          await db.execute('''
CREATE TABLE IF NOT EXISTS ClientSessions (
    SessionId INTEGER PRIMARY KEY AUTOINCREMENT,
    Username TEXT NOT NULL,
    IpAddress TEXT,
    Port INTEGER,
    ConnectedAt TEXT,
    DisconnectedAt TEXT,
    DurationSeconds INTEGER DEFAULT 0,
    SessionState TEXT
)
''');
          await db.execute('''
CREATE TABLE IF NOT EXISTS FileTransfers (
    TransferId TEXT PRIMARY KEY,
    Sender TEXT,
    Recipient TEXT,
    FileName TEXT,
    FileSize INTEGER,
    Timestamp TEXT,
    Status TEXT
)
''');
        },
      ),
    );
  }

  /// تعيين حالة جميع العملاء إلى "غير متصل" وإغلاق الجلسات المعلقة عند الإقلاع.
  Future<void> _applyStartupFixups() async {
    await _db.execute("UPDATE Clients SET Status = 'غير متصل'");
    final activeSessions =
        await _db.query('ClientSessions', where: "SessionState = 'نشطة'");
    for (final row in activeSessions) {
      final disconnectedAt = row['DisconnectedAt'];
      await _db.update(
        'ClientSessions',
        {
          'SessionState': 'منتهية بإغلاق الخادم',
          'DisconnectedAt': disconnectedAt ?? row['ConnectedAt'],
        },
        where: 'SessionId = ?',
        whereArgs: [row['SessionId']],
      );
    }
  }

  Future<void> upsertClient(String username, String ip, int port) async {
    if (username.trim().isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final existing = await _db.query(
      'Clients',
      columns: const ['Username'],
      where: 'Username = ?',
      whereArgs: [username],
    );
    if (existing.isEmpty) {
      await _db.insert('Clients', {
        'Username': username,
        'IpAddress': ip,
        'Port': port,
        'FirstSeen': now,
        'LastSeen': now,
        'TotalConnections': 1,
        'TotalMessagesSent': 0,
        'Status': 'متصل',
        'IsBanned': 0,
        'BanReason': null,
        'BannedUntil': null,
      });
    } else {
      await _db.rawUpdate(
        "UPDATE Clients SET IpAddress = ?, Port = ?, LastSeen = ?, TotalConnections = TotalConnections + 1, Status = 'متصل' WHERE Username = ?",
        [ip, port, now, username],
      );
    }
  }

  Future<void> setClientOffline(String username) async {
    if (username.trim().isEmpty) return;
    await _db.update(
      'Clients',
      {
        'Status': 'غير متصل',
        'LastSeen': DateTime.now().toIso8601String(),
      },
      where: 'Username = ?',
      whereArgs: [username],
    );
  }

  Future<void> recordBan(String username, String reason, int minutes) async {
    if (username.trim().isEmpty) return;
    await _db.rawUpdate(
      "UPDATE Clients SET IsBanned = 1, BanReason = ?, BannedUntil = ?, Status = 'محظور مؤقتاً' WHERE Username = ?",
      [reason, DateTime.now().add(Duration(minutes: minutes)).toIso8601String(), username],
    );
  }

  Future<void> saveChatMessage(
    String? sender,
    String? recipient,
    String? messageContent,
    bool isEncrypted,
    String? messageType,
    String? senderIp,
  ) async {
    final effectiveRecipient =
        (recipient == null || recipient.isEmpty) ? 'الجميع (عامة)' : recipient;
    await _db.insert('ChatMessages', {
      'Sender': sender ?? 'مجهول',
      'Recipient': effectiveRecipient,
      'MessageType': messageType ?? 'عامة',
      'MessageContent': messageContent ?? '',
      'IsEncrypted': isEncrypted ? 1 : 0,
      'Timestamp': DateTime.now().toIso8601String(),
      'SenderIp': senderIp ?? '',
    });
    await _db.rawUpdate(
      'UPDATE Clients SET TotalMessagesSent = TotalMessagesSent + 1 WHERE Username = ?',
      [sender],
    );
  }

  Future<int> startSession(String username, String ip, int port) async {
    return _db.insert('ClientSessions', {
      'Username': username,
      'IpAddress': ip,
      'Port': port,
      'ConnectedAt': DateTime.now().toIso8601String(),
      'DisconnectedAt': null,
      'DurationSeconds': 0,
      'SessionState': 'نشطة',
    });
  }

  Future<void> endSession(String username, [String reason = 'مكتملة']) async {
    final rows = await _db.query(
      'ClientSessions',
      columns: const ['SessionId', 'ConnectedAt'],
      where: "Username = ? AND SessionState = 'نشطة'",
      whereArgs: [username],
      orderBy: 'SessionId DESC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final connectedAt = DateTime.tryParse(row['ConnectedAt'] as String? ?? '');
    final now = DateTime.now();
    final duration = connectedAt == null ? 0 : (now.difference(connectedAt).inSeconds).clamp(0, 1 << 31);
    await _db.update(
      'ClientSessions',
      {
        'DisconnectedAt': now.toIso8601String(),
        'DurationSeconds': duration,
        'SessionState': reason,
      },
      where: 'SessionId = ?',
      whereArgs: [row['SessionId']],
    );
  }

  Future<void> logFileTransfer(
    String transferId,
    String sender,
    String? recipient,
    String fileName,
    int fileSize, [
    String status = 'مكتمل',
  ]) async {
    if (transferId.isEmpty) return;
    final existing = await _db.query(
      'FileTransfers',
      columns: const ['TransferId'],
      where: 'TransferId = ?',
      whereArgs: [transferId],
    );
    if (existing.isEmpty) {
      await _db.insert('FileTransfers', {
        'TransferId': transferId,
        'Sender': sender,
        'Recipient': (recipient == null || recipient.isEmpty) ? 'الجميع' : recipient,
        'FileName': fileName,
        'FileSize': fileSize,
        'Timestamp': DateTime.now().toIso8601String(),
        'Status': status,
      });
    } else {
      await _db.update(
        'FileTransfers',
        {'Status': status},
        where: 'TransferId = ?',
        whereArgs: [transferId],
      );
    }
  }

  Future<Map<String, int>> getDatabaseStats() async {
    Future<int> countAll(String table) async {
      final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      if (rows.isEmpty) return 0;
      final value = rows.first['c'];
      return value is int ? value : 0;
    }

    final clients = await countAll('Clients');
    final messages = await countAll('ChatMessages');
    final sessions = await countAll('ClientSessions');
    int dbSize = 0;
    try {
      final f = File(dbFilePath);
      if (f.existsSync()) dbSize = f.lengthSync();
    } catch (_) {}
    return {'clients': clients, 'messages': messages, 'sessions': sessions, 'dbSize': dbSize};
  }

  Future<void> clearDatabase() async {
    await _db.delete('FileTransfers');
    await _db.delete('ClientSessions');
    await _db.delete('ChatMessages');
    await _db.delete('Clients');
  }

  Future<List<Map<String, Object?>>> queryClients() async => _db.query('Clients', orderBy: 'Username');
  Future<List<Map<String, Object?>>> queryChatMessages() async => _db.query('ChatMessages', orderBy: 'MessageId DESC');
  Future<List<Map<String, Object?>>> querySessions() async => _db.query('ClientSessions', orderBy: 'SessionId DESC');
  Future<List<Map<String, Object?>>> queryFileTransfers() async => _db.query('FileTransfers', orderBy: 'Timestamp DESC');

  Future<String> buildSqlSchemaScript() async {
    final buffer = StringBuffer();
    buffer.writeln('-- =====================================================');
    buffer.writeln('-- سكربت قاعدة بيانات خادم الدردشة والشبكات (Client-Server Chat DB)');
    buffer.writeln('-- تاريخ الإنشاء: ${_nowSqlTimestamp()}');
    buffer.writeln('-- متوافق مع: SQLite, MySQL, Microsoft SQL Server, PostgreSQL');
    buffer.writeln('-- =====================================================');
    buffer.writeln();
    buffer.writeln('-- 1. جدول العملاء (Clients)');
    buffer.writeln('CREATE TABLE IF NOT EXISTS Clients (');
    buffer.writeln('    ClientId INTEGER PRIMARY KEY AUTO_INCREMENT,');
    buffer.writeln("    Username VARCHAR(100) NOT NULL UNIQUE,");
    buffer.writeln('    IpAddress VARCHAR(45),');
    buffer.writeln('    Port INT,');
    buffer.writeln('    FirstSeen DATETIME,');
    buffer.writeln('    LastSeen DATETIME,');
    buffer.writeln("    TotalConnections INT DEFAULT 0,");
    buffer.writeln("    TotalMessagesSent INT DEFAULT 0,");
    buffer.writeln("    Status VARCHAR(50) DEFAULT 'Offline',");
    buffer.writeln('    IsBanned BOOLEAN DEFAULT 0,');
    buffer.writeln('    BanReason VARCHAR(255),');
    buffer.writeln('    BannedUntil DATETIME');
    buffer.writeln(');');
    buffer.writeln();
    buffer.writeln('-- 2. جدول محتويات الرسائل والمحادثات (ChatMessages)');
    buffer.writeln('CREATE TABLE IF NOT EXISTS ChatMessages (');
    buffer.writeln('    MessageId INTEGER PRIMARY KEY AUTO_INCREMENT,');
    buffer.writeln('    Sender VARCHAR(100) NOT NULL,');
    buffer.writeln("    Recipient VARCHAR(100) DEFAULT 'ALL',");
    buffer.writeln("    MessageType VARCHAR(50) DEFAULT 'Public',");
    buffer.writeln('    MessageContent TEXT,');
    buffer.writeln('    IsEncrypted BOOLEAN DEFAULT 0,');
    buffer.writeln('    Timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,');
    buffer.writeln('    SenderIp VARCHAR(45)');
    buffer.writeln(');');
    buffer.writeln();
    buffer.writeln('-- 3. جدول جلسات اتصال العملاء (ClientSessions)');
    buffer.writeln('CREATE TABLE IF NOT EXISTS ClientSessions (');
    buffer.writeln('    SessionId INTEGER PRIMARY KEY AUTO_INCREMENT,');
    buffer.writeln('    Username VARCHAR(100) NOT NULL,');
    buffer.writeln('    IpAddress VARCHAR(45),');
    buffer.writeln('    Port INT,');
    buffer.writeln('    ConnectedAt DATETIME,');
    buffer.writeln('    DisconnectedAt DATETIME,');
    buffer.writeln('    DurationSeconds INT DEFAULT 0,');
    buffer.writeln('    SessionState VARCHAR(50)');
    buffer.writeln(');');
    buffer.writeln();
    buffer.writeln('-- 4. جدول نقل الملفات (FileTransfers)');
    buffer.writeln('CREATE TABLE IF NOT EXISTS FileTransfers (');
    buffer.writeln('    TransferId VARCHAR(100) PRIMARY KEY,');
    buffer.writeln('    Sender VARCHAR(100),');
    buffer.writeln('    Recipient VARCHAR(100),');
    buffer.writeln('    FileName VARCHAR(255),');
    buffer.writeln('    FileSize BIGINT,');
    buffer.writeln('    Timestamp DATETIME,');
    buffer.writeln('    Status VARCHAR(50)');
    buffer.writeln(');');
    return buffer.toString();
  }

  Future<void> _saveSqlSchemaScript() async {
    try {
      File(sqlSchemaPath).writeAsStringSync(await buildSqlSchemaScript(),
          encoding: utf8);
    } catch (_) {}
  }

  Future<void> exportFullDatabaseToSql(String outputPath) async {
    final buffer = StringBuffer();
    buffer.writeln('-- =====================================================');
    buffer.writeln('-- تفريغ وتصدير قاعدة بيانات المحادثة والعملاء (Full SQL Dump)');
    buffer.writeln('-- تاريخ التصدير: ${_nowSqlTimestamp()}');
    buffer.writeln('-- =====================================================');
    buffer.writeln();
    try {
      buffer.writeln(File(sqlSchemaPath).readAsStringSync(encoding: utf8));
      buffer.writeln();
    } catch (_) {}

    final clients = await queryClients();
    buffer.writeln('-- =====================================================');
    buffer.writeln('-- بيانات جدول العملاء (Clients Data: ${clients.length} سجل)');
    buffer.writeln('-- =====================================================');
    for (final row in clients) {
      final isBanned = (row['IsBanned'] ?? 0) == 1 ? 1 : 0;
      buffer.writeln("INSERT INTO Clients (Username, IpAddress, Port, FirstSeen, LastSeen, TotalConnections, TotalMessagesSent, Status, IsBanned, BanReason, BannedUntil) VALUES ('${escapeSql(row['Username'])}', '${escapeSql(row['IpAddress'])}', ${row['Port'] ?? 0}, ${_sqlDate(row['FirstSeen'])}, ${_sqlDate(row['LastSeen'])}, ${row['TotalConnections'] ?? 0}, ${row['TotalMessagesSent'] ?? 0}, '${escapeSql(row['Status'])}', $isBanned, '${escapeSql(row['BanReason'])}', ${_sqlDate(row['BannedUntil'])});");
    }
    buffer.writeln();

    final messages = await queryChatMessages();
    buffer.writeln('-- =====================================================');
    buffer.writeln('-- بيانات جدول محتويات الدردشة (ChatMessages Data: ${messages.length} رسالة)');
    buffer.writeln('-- =====================================================');
    for (final row in messages) {
      final isEnc = (row['IsEncrypted'] ?? 0) == 1 ? 1 : 0;
      buffer.writeln("INSERT INTO ChatMessages (Sender, Recipient, MessageType, MessageContent, IsEncrypted, Timestamp, SenderIp) VALUES ('${escapeSql(row['Sender'])}', '${escapeSql(row['Recipient'])}', '${escapeSql(row['MessageType'])}', '${escapeSql(row['MessageContent'])}', $isEnc, ${_sqlDate(row['Timestamp'])}, '${escapeSql(row['SenderIp'])}');");
    }
    buffer.writeln();

    final sessions = await querySessions();
    buffer.writeln('-- =====================================================');
    buffer.writeln('-- بيانات جدول جلسات الاتصال (ClientSessions Data: ${sessions.length} جلسة)');
    buffer.writeln('-- =====================================================');
    for (final row in sessions) {
      buffer.writeln("INSERT INTO ClientSessions (Username, IpAddress, Port, ConnectedAt, DisconnectedAt, DurationSeconds, SessionState) VALUES ('${escapeSql(row['Username'])}', '${escapeSql(row['IpAddress'])}', ${row['Port'] ?? 0}, ${_sqlDate(row['ConnectedAt'])}, ${_sqlDate(row['DisconnectedAt'])}, ${row['DurationSeconds'] ?? 0}, '${escapeSql(row['SessionState'])}');");
    }
    buffer.writeln();

    final files = await queryFileTransfers();
    buffer.writeln('-- =====================================================');
    buffer.writeln('-- بيانات جدول نقل الملفات (FileTransfers Data: ${files.length} سجل)');
    buffer.writeln('-- =====================================================');
    for (final row in files) {
      buffer.writeln("INSERT INTO FileTransfers (TransferId, Sender, Recipient, FileName, FileSize, Timestamp, Status) VALUES ('${escapeSql(row['TransferId'])}', '${escapeSql(row['Sender'])}', '${escapeSql(row['Recipient'])}', '${escapeSql(row['FileName'])}', ${row['FileSize'] ?? 0}, ${_sqlDate(row['Timestamp'])}, '${escapeSql(row['Status'])}');");
    }

    File(outputPath).writeAsStringSync(buffer.toString(), encoding: utf8);
  }

  Future<void> exportTableToCsv(
    List<Map<String, Object?>> rows,
    List<String> columns,
    String outputPath,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln(columns.map((c) => '"${c.replaceAll('"', '""')}"').join(','));
    for (final row in rows) {
      final fields = columns.map((col) {
        final value = row[col];
        if (value == null) return '""';
        String str;
        if (col == 'IsBanned' || col == 'IsEncrypted') {
          str = value == 1 ? 'True' : 'False';
        } else {
          str = value.toString();
        }
        return '"${str.replaceAll('"', '""')}"';
      });
      buffer.writeln(fields.join(','));
    }
    File(outputPath).writeAsStringSync(buffer.toString(), encoding: utf8);
  }

  Future<void> close() => _db.close();

  String _nowSqlTimestamp() {
    final now = DateTime.now();
    return "${now.year}-${_two(now.month)}-${_two(now.day)} ${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}";
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _sqlDate(Object? value) {
    if (value == null) return 'NULL';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return 'NULL';
    return formatSqlDate(dt);
  }
}