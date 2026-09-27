import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared/shared.dart';

/// نقل حرفي لـ AsyncClient.cs — محرك عميل السوكيت غير المتزامن.
class AsyncClient {
  Socket? _socket;
  final PacketDecoder _decoder = PacketDecoder();
  Future<void> _writeTail = Future.value();

  bool _isConnected = false;
  bool _closeFired = false;

  String? username;
  String? serverIp;
  int? serverPort;

  List<String> _lastUserList = const [];

  /// آخر نسخة معروفة من قائمة المستخدمين المتصلين (بدون الاسم الذاتي).
  List<String> get currentUsers => _lastUserList;

  final Map<String, _IncomingFileSession> _incomingFiles = {};

  /// مجلد تنزيلات الملفات المستقبلة بجوار ملف التنفيذ.
  late String downloadDirectory;

  Future<void> Function()? onConnectedSuccess;
  Future<void> Function(String error)? onConnectionFailed;
  Future<void> Function(String reason)? onDisconnected;
  Future<void> Function(List<String> users)? onUserListUpdated;
  Future<void> Function(ChatMessageModel msg)? onPublicMessage;
  Future<void> Function(ChatMessageModel msg)? onPrivateMessage;
  Future<void> Function(FileHeaderModel header)? onIncomingFileStarted;
  Future<void> Function(String transferId, int currentChunk, int totalChunks)?
      onIncomingFileProgress;
  Future<void> Function(String transferId, String savedPath)?
      onIncomingFileCompleted;
  Future<void> Function(String reason)? onKicked;
  Future<void> Function(String category, String text)? onLogMessage;
  Future<void> Function(VoiceMessageModel voice)? onVoiceMessage;
  Future<void> Function(VideoFrameModel frame)? onVideoFrame;
  Future<void> Function(CallSignalModel signal)? onCallSignal;

  AsyncClient() {
    final baseDir = p.dirname(Platform.resolvedExecutable);
    downloadDirectory = p.join(baseDir, 'ReceivedFiles');
  }

  bool get isConnected => _isConnected;

  Future<void> connect(String ip, int port, String displayName) async {
    try {
      final dir = Directory(downloadDirectory);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      username = displayName.trim();
      serverIp = ip;
      serverPort = port;

      _socket = await Socket.connect(ip, port);
      _isConnected = true;

      final handshake = Completer<NetworkPacket>();
      _initialPacket = handshake;
      unawaited(_receiveLoop());

      await _sendString(PacketType.connectRequest, username!);

      final response =
          await handshake.future.timeout(const Duration(seconds: 60));
      _initialPacket = null;

      final responseStr = utf8.decode(response.payload, allowMalformed: true);

      if (responseStr.startsWith('OK:')) {
        onConnectedSuccess?.call();
        return;
      }

      final error = responseStr.startsWith('REJECT:')
          ? responseStr.substring(7)
          : responseStr;
      await onConnectionFailed?.call(error);
      disconnect();
    } catch (e) {
      _isConnected = false;
      await onConnectionFailed?.call(e.toString());
      disconnect();
    }
  }

  Completer<NetworkPacket>? _initialPacket;

  Future<void> disconnectAsync() async {
    if (_isConnected) {
      try {
        await _sendString(PacketType.disconnect, 'وداعا');
      } catch (_) {}
    }
    disconnect();
  }

  void disconnect([String? reason]) {
    _isConnected = false;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    if (!_closeFired) {
      _closeFired = true;
      onDisconnected?.call(reason ?? 'تم قطع الاتصال بالخادم.');
    }
  }

  Future<void> sendPublicMessage(String message, {bool isEncrypted = false}) async {
    if (!_isConnected) return;
    final finalMsg = isEncrypted ? NetworkCrypto.encrypt(message) : message;
    final chatMsg = ChatMessageModel(
      sender: username ?? '',
      recipient: '',
      message: finalMsg,
      timestamp: DateTime.now(),
      isEncrypted: isEncrypted,
    );
    await _sendPacket(PacketType.publicMessage, chatMsg.serialize());
  }

  Future<void> sendPrivateMessage(String recipient, String message,
      {bool isEncrypted = false}) async {
    if (!_isConnected) return;
    final finalMsg = isEncrypted ? NetworkCrypto.encrypt(message) : message;
    final chatMsg = ChatMessageModel(
      sender: username ?? '',
      recipient: recipient,
      message: finalMsg,
      timestamp: DateTime.now(),
      isEncrypted: isEncrypted,
    );
    await _sendPacket(PacketType.privateMessage, chatMsg.serialize());
  }

  Future<void> sendVoiceMessage(
      String recipient, List<int> audioData, int durationSeconds) async {
    if (!_isConnected || audioData.isEmpty) return;
    final voice = VoiceMessageModel(
      sender: username ?? '',
      recipient: recipient,
      durationSeconds: durationSeconds,
      audioData: audioData,
      timestamp: DateTime.now(),
    );
    await _sendPacket(PacketType.voiceMessage, voice.serialize());
  }

  Future<void> sendVideoFrame(String recipient, List<int> frameData,
      List<int>? audioData) async {
    if (!_isConnected || frameData.isEmpty) return;
    final frame = VideoFrameModel(
      sender: username ?? '',
      recipient: recipient,
      frameData: frameData,
      audioData: audioData ?? const <int>[],
      timestamp: DateTime.now(),
    );
    await _sendPacket(PacketType.videoFrame, frame.serialize());
  }

  Future<void> sendCallSignal(String recipient, String signalType) async {
    if (!_isConnected || recipient.isEmpty) return;
    final signal = CallSignalModel(
      sender: username ?? '',
      recipient: recipient,
      signalType: signalType,
    );
    await _sendPacket(PacketType.callSignal, signal.serialize());
  }

  /// إرسال ملف على شكل رؤوس + قطع + إشعار اكتمال مع تقدم الإرسال.
  Future<void> sendFile(
    String filePath,
    String recipient, {
    void Function(int percent)? onProgress,
  }) async {
    if (!_isConnected) return;
    final file = File(filePath);
    if (!await file.exists()) return;

    final length = await file.length();
    final transferId = _randomHexId(8);

    final header = FileHeaderModel(
      transferId: transferId,
      fileName: p.basename(filePath),
      fileSize: length,
      sender: username ?? '',
      recipient: recipient,
    );
    await _sendPacket(PacketType.fileMetadata, header.serialize());

    final totalChunks =
        max(1, (length / PacketProtocol.maxChunkSize).ceil());

    final raf = await file.open();
    var offset = 0;
    var chunkIndex = 0;
    var bytesSent = 0;
    try {
      while (offset < length) {
        final chunkSize = min(PacketProtocol.maxChunkSize, length - offset);
        final chunkData = await raf.read(chunkSize);
        final chunkModel = FileChunkModel(
          transferId: transferId,
          chunkIndex: chunkIndex++,
          totalChunks: totalChunks,
          data: chunkData,
        );
        await _sendPacket(PacketType.fileChunk, chunkModel.serialize());
        offset += chunkData.length;
        bytesSent += chunkData.length;
        onProgress?.call((bytesSent * 100 / length).floor());
      }
    } finally {
      await raf.close();
    }

    await _sendPacket(
        PacketType.fileComplete, utf8.encode(transferId));
  }

  Future<void> _receiveLoop() async {
    try {
      var first = true;
      await for (final chunk in _socket!) {
        _decoder.write(chunk);
        while (true) {
          final packet = _decoder.tryDecode();
          if (packet == null) break;
          if (first && _initialPacket != null) {
            first = false;
            _initialPacket!.complete(packet);
            continue;
          }
          await _handlePacket(packet);
        }
      }
    } catch (e) {
      if (_isConnected) {
        await onLogMessage?.call('ERROR', 'خطأ أثناء استقبال البيانات: $e');
      }
    } finally {
      disconnect();
    }
  }

  Future<void> _handlePacket(NetworkPacket packet) async {
    switch (packet.type) {
      case PacketType.userListUpdate:
        final listStr = utf8.decode(packet.payload, allowMalformed: true);
        final users = listStr
            .split(',')
            .where((u) => u.isNotEmpty)
            .where((u) => !u.toLowerCase().contains((username ?? '').toLowerCase()))
            .toList();
        _lastUserList = users;
        await onUserListUpdated?.call(users);
        break;

      case PacketType.publicMessage:
        await onPublicMessage?.call(ChatMessageModel.deserialize(packet.payload));
        break;

      case PacketType.privateMessage:
        await onPrivateMessage?.call(ChatMessageModel.deserialize(packet.payload));
        break;

      case PacketType.fileMetadata:
        final header = FileHeaderModel.deserialize(packet.payload);
        final stamp = _timestampFilePrefix(DateTime.now());
        final savePath = p.join(downloadDirectory, '${stamp}_${header.fileName}');
        _incomingFiles[header.transferId] =
            _IncomingFileSession(header, savePath);
        await onIncomingFileStarted?.call(header);
        break;

      case PacketType.fileChunk:
        final chunk = FileChunkModel.deserialize(packet.payload);
        final session = _incomingFiles[chunk.transferId];
        if (session != null) {
          session.writeChunk(chunk.data);
          await onIncomingFileProgress
              ?.call(chunk.transferId, chunk.chunkIndex + 1, chunk.totalChunks);
        }
        break;

      case PacketType.fileComplete:
        final transferId = utf8.decode(packet.payload, allowMalformed: true);
        final session = _incomingFiles.remove(transferId);
        if (session != null) {
          await session.close();
          await onIncomingFileCompleted?.call(transferId, session.filePath);
        }
        break;

      case PacketType.voiceMessage:
        await onVoiceMessage?.call(VoiceMessageModel.deserialize(packet.payload));
        break;

      case PacketType.videoFrame:
        await onVideoFrame?.call(VideoFrameModel.deserialize(packet.payload));
        break;

      case PacketType.callSignal:
        await onCallSignal?.call(CallSignalModel.deserialize(packet.payload));
        break;

      case PacketType.kickNotice:
        final reason = utf8.decode(packet.payload, allowMalformed: true);
        await onKicked?.call(reason);
        disconnect();
        break;

      case PacketType.disconnect:
        final reason = utf8.decode(packet.payload, allowMalformed: true);
        disconnect(reason);
        break;

      case PacketType.connectRequest:
      case PacketType.connectResponse:
        break;
    }
  }

  Future<void> _sendPacket(PacketType type, List<int> payload) {
    final completer = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        _socket?.add(framePacket(type, payload));
        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    }).catchError((_) {});
    return completer.future;
  }

  Future<void> _sendString(PacketType type, String text) =>
      _sendPacket(type, text.isEmpty ? <int>[] : utf8.encode(text));

  static String _randomHexId(int length) {
    final rnd = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(rnd.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  static String _timestampFilePrefix(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}_'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _IncomingFileSession {
  _IncomingFileSession(this.header, this.filePath);

  final FileHeaderModel header;
  final String filePath;
  late final IOSink _sink;

  void writeChunk(List<int> data) {
    if (data.isEmpty) return;
    if (!_sinkOpened) {
      _open();
    }
    _sink.add(Uint8List.fromList(data));
  }

  bool _sinkOpened = false;

  void _open() {
    _sink = File(filePath)
        .openWrite(mode: FileMode.writeOnlyAppend);
    _sinkOpened = true;
  }

  Future<void> close() async {
    if (_sinkOpened) {
      _sinkOpened = false;
      await _sink.flush();
      await _sink.close();
    }
  }
}