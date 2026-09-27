import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client_app/async_client.dart';
import 'package:client_app/main.dart';
import 'package:server_app/database_manager.dart';
import 'package:server_app/database_viewer_page.dart';
import 'package:shared/shared.dart';

const double _screenW = 1280;
const double _screenH = 800;

const String _dbDir2 = r'C:\Users\ADMINI~1\AppData\Local\Temp\opencode\srv_db2';

Widget _wrap(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E88E5),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
    ),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: _screenW,
        height: _screenH,
        child: child,
      ),
    ),
  );
}

void _drain(WidgetTester tester) {
  for (var i = 0; i < 20; i++) {
    if (tester.takeException() == null) break;
  }
}

void _mockPlatformChannels() {
  AudioplayersPlatformInterface.instance = _FakeAudioPlatform();
  GlobalAudioplayersPlatformInterface.instance = _FakeGlobalAudioPlatform();
  const record = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(record, (call) async {
    switch (call.method) {
      case 'create':
        return null;
      case 'hasPermission':
        return true;
      case 'start':
        return null;
      case 'stop':
        return null;
      case 'dispose':
        return null;
      default:
        return null;
    }
  });
  const auGlobal = MethodChannel('xyz.luan/audioplayers.global');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(auGlobal, (call) async {
    return call.method == 'create' ? 1 : null;
  });
  const auGlobalEv = EventChannel('xyz.luan/audioplayers.global/events');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    auGlobalEv,
    MockStreamHandler.inline(
      onListen: (args, events) {},
      onCancel: (args) {},
    ),
  );
  const auEv = EventChannel('xyz.luan/audioplayers/events');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    auEv,
    MockStreamHandler.inline(
      onListen: (args, events) {},
      onCancel: (args) {},
    ),
  );
  const au = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(au, (call) async {
    return null;
  });
  const cam = MethodChannel('plugins.flutter.io/camera_avfoundation');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(cam, (call) async => null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture: شاشة الاتصال', (WidgetTester tester) async {
    _mockPlatformChannels();
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(ConnectionScreen),
      matchesGoldenFile('captured/01_connection.png'),
    );
  });

  testWidgets('capture: شاشة الدردشة', (WidgetTester tester) async {
    _mockPlatformChannels();
    final client = _FakeClient();
    client.username = 'أحمد';
    client.serverIp = '192.168.128.243';
    client.serverPort = 8989;
    await tester.pumpWidget(_wrap(ChatScreen(client: client)));
    await tester.pump(const Duration(milliseconds: 300));
    client.onUserListUpdated!(['زياد', 'سارة', 'محمد']);
    client.onPublicMessage!(_msg('سارة', '', 'مرحباً بالجميع، كيف حالكم؟'));
    client.onPublicMessage!(_msg('محمد', '', 'أهلاً وسهلاً!'));
    client.onPrivateMessage!(
        _msg('سارة', 'أحمد', 'مرحباً أحمد، هل استلمت الملف؟'));
    client.onVoiceMessage!(
        _voice('محمد', '', 5, 4000, 'الرسالة الصوتية النصية'));
    client.onIncomingFileStarted!(
        _fileHeader('fid-1', 'تقرير_المشروع.docx', 24576, 'سارة', ''));
    client.onIncomingFileCompleted!(
        'fid-1', r'C:\Downloads\تقرير_المشروع.docx');
    await tester.pump(const Duration(milliseconds: 400));
    _drain(tester);
    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('captured/02_chat_hub.png'),
    );
  });

  testWidgets('capture: عارض قاعدة البيانات', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    initDatabaseFactoryNoIsolate();
    DatabaseManager? db;
    await tester.runAsync(() async {
      db = await DatabaseManager.create(dbDirectory: _dbDir2);
      await db!.upsertClient('أحمد', '192.168.128.20', 51234);
      await db!.upsertClient('سارة', '192.168.128.21', 51235);
      await db!.saveChatMessage(
          'سارة', '', 'مرحباً بالجميع من سارة!', false, 'عامة', '192.168.128.21');
      await db!.saveChatMessage('أحمد', 'سارة', 'أهلاً سارة، هل استلمت الملف؟',
          true, 'خاصة مشفرة', '192.168.128.20');
      await db!.startSession('أحمد', '192.168.128.20', 51234);
      await db!.endSession('أحمد');
      await db!.logFileTransfer('fid-9', 'سارة', 'أحمد', 'تقرير.pdf', 4096);
    });
    final mgr = db!;
    await tester.pumpWidget(DefaultTabController(
        length: 4, child: _wrap(DatabaseViewerPage(db: mgr))));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    _drain(tester);
    await expectLater(
      find.byType(DatabaseViewerPage),
      matchesGoldenFile('captured/04_database.png'),
    );
    await tester.runAsync(() => mgr.close());
  });
}

class _FakeClient extends FakeAsyncClient {
  @override
  void disconnect([String? reason]) {}
}

class FakeAsyncClient extends AsyncClient {
  @override
  void disconnect([String? reason]) {}
}

class _FakeAudioPlatform extends AudioplayersPlatformInterface {
  @override
  Future<void> create(String playerId) async {}
  @override
  Future<void> dispose(String playerId) async {}
  @override
  Stream<AudioEvent> getEventStream(String playerId) => const Stream.empty();
  @override
  Future<void> pause(String playerId) async {}
  @override
  Future<void> stop(String playerId) async {}
  @override
  Future<void> resume(String playerId) async {}
  @override
  Future<void> release(String playerId) async {}
  @override
  Future<void> seek(String playerId, Duration position) async {}
  @override
  Future<void> setBalance(String playerId, double balance) async {}
  @override
  Future<void> setVolume(String playerId, double volume) async {}
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}
  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}
  @override
  Future<void> setSourceUrl(String playerId, String url,
      {bool? isLocal, String? mimeType}) async {}
  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes,
      {String? mimeType}) async {}
  @override
  Future<void> setAudioContext(
      String playerId, AudioContext audioContext) async {}
  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}
  @override
  Future<int?> getDuration(String playerId) async => 0;
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<void> emitLog(String playerId, String message) async {}
  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

class _FakeGlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
}

ChatMessageModel _msg(String sender, String recipient, String text) {
  return ChatMessageModel(
    sender: sender,
    recipient: recipient,
    message: text,
    timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
  );
}

VoiceMessageModel _voice(String sender, String recipient, int durationSeconds,
    int dataLen, String label) {
  return VoiceMessageModel(
    sender: sender,
    recipient: recipient,
    durationSeconds: durationSeconds,
    audioData: List<int>.generate(dataLen, (i) => i % 251),
  );
}

FileHeaderModel _fileHeader(String id, String name, int size, String sender,
    String recipient) {
  return FileHeaderModel(
    transferId: id,
    fileName: name,
    fileSize: size,
    sender: sender,
    recipient: recipient,
  );
}