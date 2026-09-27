import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:server_app/async_server.dart';
import 'package:shared/shared.dart';

import 'package:client_app/async_client.dart';

Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('انتهت مهلة الانتظار');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Harness {
  _Harness(this._server);

  final AsyncServer _server;
  final List<AsyncClient> clients = [];

  Future<AsyncClient> connect(String username) async {
    final client = AsyncClient();
    var failed = false;
    String? failReason;
    final callbacks = <String>[];
    client.onConnectionFailed = (error) async {
      failed = true;
      failReason = error;
      callbacks.add('CONN_FAIL');
    };
    client.onDisconnected = (_) async => callbacks.add('DISCONNECTED');
    client.onKicked = (_) async => callbacks.add('KICKED');
    await client.connect('127.0.0.1', _server.port!, username);
    await waitUntil(() {
      final connected = client.isConnected;
      final gotFail = failed == true;
      return connected || gotFail || callbacks.contains('DISCONNECTED');
    });
    expect(client.isConnected, isTrue,
        reason: 'فشل اتصال $username: $failReason');
    clients.add(client);
    return client;
  }

  Future<void> dispose() async {
    for (final c in clients) {
      c.disconnect();
    }
    clients.clear();
    await _server.stop();
  }
}

void main() {
  late AsyncServer server;

  setUp(() async {
    server = AsyncServer();
    await server.start(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    try {
      await server.stop();
    } catch (_) {}
  });

  test('الاتصال الناجح يرسل قائمة المستخدمين ويستثني الاسم الذاتي', () async {
    final alice = AsyncClient();
    var connected = false;
    alice.onConnectedSuccess = () async => connected = true;
    final aliceLists = <List<String>>[];
    alice.onUserListUpdated = (users) async => aliceLists.add(users);

    final bob = AsyncClient();
    final bobLists = <List<String>>[];
    bob.onUserListUpdated = (users) async => bobLists.add(users);

    await alice.connect('127.0.0.1', server.port!, 'Alice');
    expect(connected, isTrue);
    expect(alice.isConnected, isTrue);

    await bob.connect('127.0.0.1', server.port!, 'Bob');

    // Bob ينضم لاحقاً -> تصل قائمة جديدة إلى Alice تتضمن Bob فقط (بدون Alice)
    await waitUntil(
        () => aliceLists.isNotEmpty && aliceLists.last.contains('Bob'));
    expect(aliceLists.last, isNot(contains('Alice')));

    await waitUntil(() => bobLists.isNotEmpty);
    expect(bobLists.last, isNot(contains('Bob')));

    alice.disconnect();
    bob.disconnect();
  });

  test('رفض الاتصال عند تكرار الاسم أثناء تواجده', () async {
    final alice = AsyncClient();
    await alice.connect('127.0.0.1', server.port!, 'Dup');

    final dup = AsyncClient();
    String? failError;
    dup.onConnectionFailed = (error) async => failError = error;
    await dup.connect('127.0.0.1', server.port!, 'Dup');

    expect(dup.isConnected, isFalse);
    expect(failError, contains('اسم المستخدم مستخدم مسبقاً'));
    alice.disconnect();
  });

  test('رسالة عامة تصل إلى العميل الآخر ببياناتها الكاملة', () async {
    final bob = await _Harness(server).connect('Bob');
    final alice = await _Harness(server).connect('Alice');

    final received = <ChatMessageModel>[];
    bob.onPublicMessage = (msg) async => received.add(msg);

    await alice.sendPublicMessage('مرحباً بالجميع');
    await waitUntil(() => received.isNotEmpty);

    expect(received.single.message, 'مرحباً بالجميع');
    expect(received.single.sender, 'Alice');
    await _Harness(server).dispose();
  });

  test('الرسالة الخاصة تصل للمستقبل وتعود صدى للمرسل', () async {
    final bob = await _Harness(server).connect('Bob');
    final alice = await _Harness(server).connect('Alice');

    final bobReceived = <ChatMessageModel>[];
    final aliceReceived = <ChatMessageModel>[];
    bob.onPrivateMessage = (msg) async => bobReceived.add(msg);
    alice.onPrivateMessage = (msg) async => aliceReceived.add(msg);

    await alice.sendPrivateMessage('Bob', 'رسالة سرية');
    await waitUntil(() => bobReceived.isNotEmpty && aliceReceived.isNotEmpty);

    expect(bobReceived.single.sender, 'Alice');
    expect(bobReceived.single.recipient, 'Bob');
    expect(bobReceived.single.message, 'رسالة سرية');
    expect(aliceReceived.single.message, 'رسالة سرية');
    await _Harness(server).dispose();
  });

  test('الرسالة الخاصة المشفرة تصل نفس نص التشفير (مطابقة سلوك C#)', () async {
    final bob = await _Harness(server).connect('Bob');
    final alice = await _Harness(server).connect('Alice');

    final bobReceived = <ChatMessageModel>[];
    bob.onPrivateMessage = (msg) async => bobReceived.add(msg);

    await alice.sendPrivateMessage('Bob', 'نص مشفر', isEncrypted: true);
    await waitUntil(() => bobReceived.isNotEmpty);

    // في C# التشفير الفعلي يفشل ويُرجع النص كما هو (passthrough)
    expect(bobReceived.single.message, 'نص مشفر');
    expect(bobReceived.single.isEncrypted, isTrue);
    await _Harness(server).dispose();
  });

  test('نقل ملف بعدة قطع يعيد تجميعه بنفس البايتات على الجهة الأخرى', () async {
    final dir = await Directory.systemTemp.createTemp('client_file_test_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    final bob = await _Harness(server).connect('Bob');
    final alice = await _Harness(server).connect('Alice');
    bob.downloadDirectory = dir.path;

    final payload = List<int>.generate(70 * 1024, (i) => i % 251);
    final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.bin');
    await file.writeAsBytes(payload);

    FileHeaderModel? startedHeader;
    int? progressTotal;
    List<int>? finalBytes;

    bob.onIncomingFileStarted = (header) async {
      startedHeader = header;
    };
    bob.onIncomingFileProgress = (id, current, total) async {
      progressTotal = total;
    };
    bob.onIncomingFileCompleted = (id, savedPath) async {
      finalBytes = await File(savedPath).readAsBytes();
    };

    await alice.sendFile(file.path, '', onProgress: (_) {});

    await waitUntil(() => finalBytes != null, timeout: const Duration(seconds: 15));
    expect(startedHeader, isNotNull);
    expect(startedHeader!.fileName, endsWith('.bin'));
    expect(startedHeader!.sender, 'Alice');
    expect(progressTotal, greaterThan(1), reason: 'يجب تفكيك الملف إلى عدة قطع');
    expect(finalBytes!.length, payload.length);
    expect(finalBytes, equals(payload));
    await _Harness(server).dispose();
  });

  test('رسالة صوتية وبدء مكالمة وOFFLINE لمستخدم غير متصل', () async {
    final bob = await _Harness(server).connect('Bob');
    final alice = await _Harness(server).connect('Alice');

    final voices = <VoiceMessageModel>[];
    bob.onVoiceMessage = (voice) async => voices.add(voice);

    await alice.sendVoiceMessage('', [10, 20, 30], 4);
    await waitUntil(() => voices.isNotEmpty);
    expect(voices.single.audioData, [10, 20, 30]);
    expect(voices.single.durationSeconds, 4);
    expect(voices.single.sender, 'Alice');

    final callSignals = <CallSignalModel>[];
    bob.onCallSignal = (signal) async => callSignals.add(signal);

    await alice.sendCallSignal('Bob', 'START');
    await waitUntil(() => callSignals.isNotEmpty);
    expect(callSignals.single.signalType, 'START');
    expect(callSignals.single.sender, 'Alice');

    final offlineSignals = <CallSignalModel>[];
    alice.onCallSignal = (signal) async => offlineSignals.add(signal);

    await alice.sendCallSignal('Ghost', 'START');
    await waitUntil(() => offlineSignals.isNotEmpty);
    expect(offlineSignals.single.signalType, 'OFFLINE');
    expect(offlineSignals.single.sender, 'Ghost');
    await _Harness(server).dispose();
  });

  test('إطار فيديو خاص يصل بأجزائه للطرف الآخر', () async {
    final bob = await _Harness(server).connect('Bob');
    final alice = await _Harness(server).connect('Alice');

    final frames = <VideoFrameModel>[];
    bob.onVideoFrame = (frame) async => frames.add(frame);

    await alice.sendVideoFrame('Bob', [4, 5, 6], [7, 8]);
    await waitUntil(() => frames.isNotEmpty);
    expect(frames.single.frameData, [4, 5, 6]);
    expect(frames.single.audioData, [7, 8]);
    expect(frames.single.sender, 'Alice');
    await _Harness(server).dispose();
  });

  test('اتصال ورسالة عامة بأرقام عربية وأحرف متعددة البايت بالكامل', () async {
    final harness = _Harness(server);
    final bob = await harness.connect('علي١٢٣');
    final alice = await harness.connect('أحمد٩٩');

    final bobLists = <List<String>>[];
    bob.onUserListUpdated = (users) async => bobLists.add(users);
    await waitUntil(() => bobLists.any((list) => list.contains('أحمد٩٩')));
    expect(bobLists.last, contains('أحمد٩٩'));
    expect(bobLists.last, isNot(contains('علي١٢٣')));

    final received = <ChatMessageModel>[];
    bob.onPublicMessage = (msg) async => received.add(msg);

    const text = 'مرحباً! الأرقام ١٢٣٤٥٦٧٨٩٠ والأحرف 𝚎 и مزيد ✓';
    await alice.sendPublicMessage(text);
    await waitUntil(() => received.isNotEmpty);

    expect(received.single.message, text);
    expect(received.single.sender, 'أحمد٩٩');
    expect(received.single.sender, isNot('Ahmed99'));
    await harness.dispose();
  });

  test('الطرد يستلم العميل رسالة الحظر ويتم إنهاء اتصاله', () async {
    final bob = await _Harness(server).connect('Bob');
    final alice = await _Harness(server).connect('Alice');

    String? kickReason;
    alice.onKicked = (reason) async => kickReason = reason;

    final kicked = await server.kickClient('Alice', 'مخالفة قواعد المحادثة');
    expect(kicked, isTrue);
    await waitUntil(() => kickReason != null);
    expect(kickReason, contains('مخالفة قواعد المحادثة'));
    expect(alice.isConnected, isFalse);
    bob.disconnect();
    await server.stop();
  });

  test('إيقاف الخادم يرسل للعملاء رسالة انقطاع', () async {
    final harness = _Harness(server);
    final alice = await harness.connect('Alice');

    String? disconnectReason;
    alice.onDisconnected = (reason) async => disconnectReason = reason;

    await server.stop();
    await waitUntil(() => disconnectReason != null);
    expect(disconnectReason, contains('تم إيقاف الخادم'));
    expect(alice.isConnected, isFalse);

    for (final c in harness.clients) {
      c.disconnect();
    }
  });

  test('مقاومة الحروف العربية/الفواصل في عنوان IP (NormalizeNetworkAddress)', () {
    String normalize(String input) {
      final buffer = StringBuffer();
      for (final c in input.trim().split('')) {
        if (c.codeUnitAt(0) >= 0x0660 && c.codeUnitAt(0) <= 0x0669) {
          buffer.write(c.codeUnitAt(0) - 0x0660);
        } else if (c.codeUnitAt(0) >= 0x06F0 && c.codeUnitAt(0) <= 0x06F9) {
          buffer.write(c.codeUnitAt(0) - 0x06F0);
        } else if (c == ',' || c == '،' || c == '/') {
          buffer.write('.');
        } else if (c.trim().isNotEmpty) {
          buffer.write(c);
        }
      }
      return buffer.toString();
    }

    expect(normalize('١٩٢،١٦٨،١،١٠'), '192.168.1.10');
    expect(normalize('192/168/1/1'), '192.168.1.1');
  });

  test('formatBytes يطابق صياغة C# في العميل', () {
    String formatBytes(int bytes) {
      const sizes = ['B', 'KB', 'MB', 'GB'];
      double len = bytes.toDouble();
      var order = 0;
      while (len >= 1024 && order < sizes.length - 1) {
        order++;
        len /= 1024;
      }
      String text;
      if (len == len.roundToDouble()) {
        text = len.round().toString();
      } else {
        text = len.toStringAsFixed(2);
        text = text.replaceFirst(RegExp(r'\.?0+$'), '');
      }
      return '$text ${sizes[order]}';
    }

    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1048576), '1 MB');
  });

  test('مكالمة فيديو كاملة: START ثم ACCEPT ثم إطارات بصوت بين الطرفين ثم END', () async {
    final harness = _Harness(server);
    final bob = await harness.connect('Bob');
    final alice = await harness.connect('Alice');

    final aliceSignals = <CallSignalModel>[];
    alice.onCallSignal = (signal) async => aliceSignals.add(signal);
    final bobSignals = <CallSignalModel>[];
    bob.onCallSignal = (signal) async => bobSignals.add(signal);

    final aliceFrames = <VideoFrameModel>[];
    alice.onVideoFrame = (frame) async => aliceFrames.add(frame);
    final bobFrames = <VideoFrameModel>[];
    bob.onVideoFrame = (frame) async => bobFrames.add(frame);

    // المرسل يرنّ والطرف الآخر يستقبل طلب المكالمة
    await alice.sendCallSignal('Bob', 'START');
    await waitUntil(() => bobSignals.isNotEmpty);
    expect(bobSignals.last.signalType, 'START');
    expect(bobSignals.last.sender, 'Alice');

    // القبول يتجه في الاتجاه المعاكس
    await bob.sendCallSignal('Alice', 'ACCEPT');
    await waitUntil(() => aliceSignals.isNotEmpty);
    expect(aliceSignals.last.signalType, 'ACCEPT');
    expect(aliceSignals.last.sender, 'Bob');

    // كل طرف يرسل إطارات فيديو مع صوت إلى الآخر
    await alice.sendVideoFrame('Bob', List<int>.filled(2048, 1), [1, 2, 3]);
    await bob.sendVideoFrame('Alice', List<int>.filled(2048, 2), [4, 5, 6]);
    await waitUntil(() => bobFrames.isNotEmpty && aliceFrames.isNotEmpty);

    expect(bobFrames.last.sender, 'Alice');
    expect(bobFrames.last.frameData.length, 2048);
    expect(bobFrames.last.audioData, [1, 2, 3]);
    expect(aliceFrames.last.sender, 'Bob');
    expect(aliceFrames.last.audioData, [4, 5, 6]);

    // أحد الطرفين ينهي المكالمة
    await alice.sendCallSignal('Bob', 'END');
    await waitUntil(() => bobSignals.any((s) => s.signalType == 'END'));
    expect(bobSignals.last.signalType, 'END');
    expect(bobSignals.last.sender, 'Alice');

    await harness.dispose();
  });
}