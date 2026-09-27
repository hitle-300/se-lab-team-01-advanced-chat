import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:server_app/async_server.dart';
import 'package:server_app/database_manager.dart';
import 'package:shared/shared.dart';

class TestClient {
  TestClient(this.socket) {
    _sub = socket.listen((chunk) {
      decoder.write(chunk);
      while (true) {
        final p = decoder.tryDecode();
        if (p == null) break;
        if (_waiters.isNotEmpty) {
          _waiters.removeAt(0).complete(p);
        } else {
          _buffer.add(p);
        }
      }
    });
  }

  final Socket socket;
  final PacketDecoder decoder = PacketDecoder();
  final _buffer = <NetworkPacket>[];
  final _waiters = <Completer<NetworkPacket>>[];
  late final StreamSubscription<List<int>> _sub;

  NetworkPacket? buffered() => _buffer.isNotEmpty ? _buffer.first : null;

  void send(PacketType type, List<int> payload) {
    socket.add(framePacket(type, payload));
  }

  Future<NetworkPacket> next() async {
    if (_buffer.isNotEmpty) return _buffer.removeAt(0);
    final c = Completer<NetworkPacket>();
    _waiters.add(c);
    try {
      return await c.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw StateError('انتهت مهلة انتظار الحزمة');
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    socket.destroy();
  }

  Future<void> drainUserLists() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    while (_buffer.isNotEmpty) {
      final p = _buffer.removeAt(0);
      if (p.type != PacketType.userListUpdate) {
        _buffer.insert(0, p);
        return;
      }
    }
  }
}

Future<TestClient> connectAs(String username, int port) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final client = TestClient(socket);
  client.send(PacketType.connectRequest, utf8.encode(username));
  return client;
}

void main() {
  initDatabaseFactory();

  late Directory tempDir;
  late DatabaseManager db;
  late AsyncServer server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('server_test_');
    db = await DatabaseManager.create(dbDirectory: tempDir.path);
    server = AsyncServer(database: db);
    await server.start(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.stop();
    await db.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('المصافحة والتسجيل', () {
    test('قبول عميل وإضافة قائمة المستخدمين', () async {
      final a = await connectAs('Ahmed', server.port!);

      final ok = await a.next();
      expect(ok.type, PacketType.connectResponse);
      expect(ok.payloadAsUtf8, startsWith('OK:'));

      final list = await a.next();
      expect(list.type, PacketType.userListUpdate);
      expect(list.payloadAsUtf8, 'Ahmed');

      await a.close();
    });

    test('رفض بروتوكول غير صالح عند أول حزمة', () async {
      final socket = await Socket.connect('127.0.0.1', server.port!);
      final client = TestClient(socket);
      client.send(PacketType.publicMessage, utf8.encode('hi'));

      final response = await client.next();
      expect(response.type, PacketType.connectResponse);
      expect(response.payloadAsUtf8, 'REJECT:بروتوكول غير صالح');
      await client.close();
    });

    test('رفض اسم فارغ', () async {
      final socket = await Socket.connect('127.0.0.1', server.port!);
      final client = TestClient(socket);
      client.send(PacketType.connectRequest, utf8.encode('   '));

      final response = await client.next();
      expect(response.payloadAsUtf8, 'REJECT:اسم المستخدم فارغ');
      await client.close();
    });

    test('رفض اسم مستخدم مكرر', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();

      final b = await connectAs('Ahmed', server.port!);
      final response = await b.next();
      expect(response.payloadAsUtf8, 'REJECT:اسم المستخدم مستخدم مسبقاً');

      await a.close();
      await b.close();
    });

    test('رفض الاسم رغم اختلاف الحروف الكبيرة (OrdinalIgnoreCase)', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();

      final b = await connectAs('ahmed', server.port!);
      final response = await b.next();
      expect(response.payloadAsUtf8, 'REJECT:اسم المستخدم مستخدم مسبقاً');

      await a.close();
      await b.close();
    });

    test('رفض الموافقة من المدير', () async {
      final temp2 = await Directory.systemTemp.createTemp('server_reject_');
      final db2 = await DatabaseManager.create(dbDirectory: temp2.path);
      final server2 = AsyncServer(database: db2);
      server2.approveConnection =
          (username, session) async => username == 'allowed';
      await server2.start(InternetAddress.loopbackIPv4, 0);

      final client = await connectAs('X', server2.port!);
      final response = await client.next();
      expect(response.payloadAsUtf8, 'REJECT:تم رفض طلب اتصالك من قبل مدير الخادم.');

      final allowed = await connectAs('allowed', server2.port!);
      final ok = await allowed.next();
      expect(ok.payloadAsUtf8, startsWith('OK:'));

      await client.close();
      await allowed.close();
      await server2.stop();
      await db2.close();
      try {
        temp2.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  group('التوجيه والبث', () {
    test('رسالة عامة تصل للجميع مع اسم المرسل', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();
      await a.next();

      final b = await connectAs('Sara', server.port!);
      await b.next();
      await b.next();
      await a.drainUserLists();
      await b.drainUserLists();

      final msg = ChatMessageModel(
        sender: 'x',
        recipient: '',
        message: 'مرحبا بالجميع',
        timestamp: DateTime.now(),
      );
      a.send(PacketType.publicMessage, msg.serialize());

      final receivedB = await b.next();
      expect(receivedB.type, PacketType.publicMessage);
      final decoded = ChatMessageModel.deserialize(receivedB.payload);
      expect(decoded.message, 'مرحبا بالجميع');
      expect(decoded.sender, 'Ahmed');

      final receivedA = await a.next();
      expect(receivedA.type, PacketType.publicMessage);
      expect(ChatMessageModel.deserialize(receivedA.payload).sender, 'Ahmed');

      await a.close();
      await b.close();
    });

    test('رسالة خاصة تصل للمستقبل والمرسل ويتضمن رسالة نظام عند عدم توفر المستلم', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();
      await a.next();

      final b = await connectAs('Sara', server.port!);
      await b.next();
      await b.next();
      await a.drainUserLists();
      await b.drainUserLists();

      a.send(PacketType.privateMessage,
          ChatMessageModel(sender: 'x', recipient: 'Sara', message: 'همسة').serialize());

      final toB = await b.next();
      final fromA = await a.next();
      expect(toB.type, PacketType.privateMessage);
      expect(ChatMessageModel.deserialize(toB.payload).message, 'همسة');
      expect(ChatMessageModel.deserialize(fromA.payload).recipient, 'Sara');

      a.send(PacketType.privateMessage,
          ChatMessageModel(sender: 'x', recipient: 'Nobody', message: 'خارج').serialize());
      final sys = await a.next();
      expect(ChatMessageModel.deserialize(sys.payload).sender, 'SYSTEM');

      await a.close();
      await b.close();
    });

    test('قطع الملفات تُبث للجميع باستثناء المرسل', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();
      await a.next();

      final b = await connectAs('Sara', server.port!);
      await b.next();
      await b.next();
      await a.drainUserLists();
      await b.drainUserLists();

      final chunk = FileChunkModel(
        transferId: 't1',
        chunkIndex: 0,
        totalChunks: 1,
        data: [1, 2, 3],
      );
      a.send(PacketType.fileChunk, chunk.serialize());

      final received = await b.next();
      expect(received.type, PacketType.fileChunk);
      expect(FileChunkModel.deserialize(received.payload).data, [1, 2, 3]);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(a.buffered(), isNull, reason: 'المرسل يجب ألا يستقبل قطعة ملفه');

      await a.close();
      await b.close();
    });

    test('إشارات المكالمة: بدء لعميل متصل، وOFFLINE لعميل غير متصل', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();
      await a.next();

      final b = await connectAs('Sara', server.port!);
      await b.next();
      await b.next();
      await a.drainUserLists();
      await b.drainUserLists();

      a.send(PacketType.callSignal,
          CallSignalModel(sender: 'x', recipient: 'Sara', signalType: 'START').serialize());

      final toB = await b.next();
      expect(toB.type, PacketType.callSignal);
      expect(CallSignalModel.deserialize(toB.payload).signalType, 'START');
      expect(CallSignalModel.deserialize(toB.payload).sender, 'Ahmed');

      a.send(PacketType.callSignal,
          CallSignalModel(sender: 'x', recipient: 'Nobody', signalType: 'START').serialize());

      final offline = await a.next();
      expect(CallSignalModel.deserialize(offline.payload).signalType, 'OFFLINE');

      await a.close();
      await b.close();
    });
  });

  group('الطرد والحظر', () {
    test('طرد عميل ثم منع إعادة الاتصال بحظر 5 دقائق', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();
      await a.next();

      final b = await connectAs('Mohammed', server.port!);
      await b.next();
      await b.next();
      await a.drainUserLists();
      await b.drainUserLists();

      final kicked = await server.kickClient('Mohammed', 'تجاوز القوانين');
      expect(kicked, true);

      final notice = await b.next();
      expect(notice.type, PacketType.kickNotice);
      expect(notice.payloadAsUtf8, contains('تجاوز القوانين'));

      final again = await connectAs('Mohammed', server.port!);
      final reject = await again.next();
      expect(reject.type, PacketType.connectResponse);
      expect(reject.payloadAsUtf8, startsWith('REJECT:لقد تم طردك بسبب: تجاوز القوانين'));
      expect(reject.payloadAsUtf8, contains('5 دقائق'));

      await a.close();
      await b.close();
      await again.close();
    });

    test('طرد عميل غير موجود ينتج false', () async {
      expect(await server.kickClient('ghost', 'سبب'), false);
    });

    test('انتهاء مدة الحظر (0 دقائق) يسمح بإعادة الاتصال فوراً', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();
      await a.next();
      await a.drainUserLists();

      final kicked = await server.kickClient('Ahmed', 'حظر لحظي', banMinutes: 0);
      expect(kicked, true);
      final notice = await a.next();
      expect(notice.type, PacketType.kickNotice);

      await a.close();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final again = await connectAs('Ahmed', server.port!);
      final ok = await again.next();
      expect(ok.type, PacketType.connectResponse);
      expect(ok.payloadAsUtf8, startsWith('OK:'),
          reason: 'انتهاء مدة الحظر يجب أن يسمح بالعودة بلا رفض');
      await again.close();
    });
  });

  group('النزول من الشبكة', () {
    test('رسالة انقطاع صريحة لا تطرد ولا تحظر', () async {
      final a = await connectAs('Ahmed', server.port!);
      await a.next();
      await a.next();

      a.send(PacketType.disconnect, const []);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await a.close();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.connectedClients, isEmpty);

      final again = await connectAs('Ahmed', server.port!);
      final ok = await again.next();
      expect(ok.payloadAsUtf8, startsWith('OK:'));
      await again.close();
    });

    test('انقطاع عميل أثناء نقل ملف ثم إعادة اتصال سليمة', () async {
      final a = await connectAs('Ali', server.port!);
      await a.next();
      await a.next();

      final b = await connectAs('Sara', server.port!);
      await b.next();
      await b.next();
      await a.drainUserLists();
      await b.drainUserLists();

      // بدء نقل ملف كبير ثم قطع مفاجئ وسط النقل
      a.send(
        PacketType.fileMetadata,
        FileHeaderModel(
          transferId: 't-big',
          fileName: 'film_full.bin',
          fileSize: 500 * 1024 * 1024,
          sender: 'x',
          recipient: '',
        ).serialize(),
      );
      a.send(
        PacketType.fileChunk,
        FileChunkModel(
          transferId: 't-big',
          chunkIndex: 0,
          totalChunks: 20,
          data: [1, 2, 3],
        ).serialize(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await a.close();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // إعادة الاتصال بالاسم نفسه بعد الانقطاع
      final again = await connectAs('Ali', server.port!);
      final ok = await again.next();
      expect(ok.type, PacketType.connectResponse);
      expect(ok.payloadAsUtf8, startsWith('OK:'));

      // العميل الآخر ما زال حياً ويستقبل رسالة عامة من المعاد اتصاله
      again.send(
        PacketType.publicMessage,
        ChatMessageModel(
          sender: 'x',
          recipient: '',
          message: 'عدت بعد الانقطاع',
        ).serialize(),
      );
      NetworkPacket? publicPacket;
      while (publicPacket == null || publicPacket.type != PacketType.publicMessage) {
        final candidate = await b.next();
        if (candidate.type == PacketType.publicMessage) publicPacket = candidate;
      }
      expect(ChatMessageModel.deserialize(publicPacket.payload).sender, 'Ali');
      expect(ChatMessageModel.deserialize(publicPacket.payload).message, 'عدت بعد الانقطاع');

      await again.close();
      await b.close();
    });
  });

  group('تنسيق الحجم', () {
    test('formatBytes يطابق صياغة C#', () {
      expect(AsyncServer.formatBytes(500), '500 B');
      expect(AsyncServer.formatBytes(1024), '1 KB');
      expect(AsyncServer.formatBytes(1536), '1.5 KB');
      expect(AsyncServer.formatBytes(1048576), '1 MB');
    });
  });
}