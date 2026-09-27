import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared/shared.dart';

import 'banned_entry.dart';
import 'client_session.dart';
import 'database_manager.dart';

typedef ConnectionApproval = Future<bool> Function(String username, ClientSession session);

String formatDurationMmSs(DateTime start, DateTime end) {
  final duration = end.difference(start);
  return '${duration.inMinutes.toString().padLeft(2, '0')}'
      ':${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class AsyncServer {
  AsyncServer({DatabaseManager? database}) : _db = database;

  final DatabaseManager? _db;
  bool _isRunning = false;
  ServerSocket? _listener;
  final Map<String, ClientSession> _clients = {};
  final Map<String, BannedEntry> _bannedEntries = {};
  final Map<String, DateTime> _activeCallStartTimes = {};

  /// يُتتبع وجهة كل نقل ملف: transferId → recipientUsername (أو '' للعام)
  final Map<String, String> _fileTransferTargets = {};

  int _totalBytes = 0;
  int _totalPackets = 0;

  InternetAddress? listeningIp;
  int? port;

  ConnectionApproval? approveConnection;

  void Function(String type, String source, String message)? onLog;
  void Function(ClientSession session)? onClientJoined;
  void Function(ClientSession session)? onClientLeft;
  void Function(int totalBytes, int totalPackets)? onStatsUpdated;
  void Function(bool running)? onStateChanged;

  bool get isRunning => _isRunning;
  int get totalBytes => _totalBytes;
  int get totalPackets => _totalPackets;

  /// ينشئ مجلد سجل الأحداث logs/ بجوار ملف التشغيل إن لم يكن موجوداً.
  static Future<Directory> ensureLogsDirectory() async {
    final dir = Directory('logs');
    await dir.create(recursive: true);
    return dir;
  }

  List<ClientSession> get connectedClients => _clients.values.toList();

  Future<void> start(InternetAddress ip, int port) async {
    if (_isRunning) return;

    listeningIp = ip;
    this.port = port;

    try {
      await ensureLogsDirectory();
      _listener = await ServerSocket.bind(ip, port, shared: true);
    } catch (_) {
      rethrow;
    }
    this.port = _listener!.port;
    _isRunning = true;

    _log('INFO', 'SERVER', 'تم بدء تشغيل الخادم بنجاح على العنوان: ${ip.address}:${this.port}');

    await _logLanIps(port);

    onStateChanged?.call(true);

    unawaited(_acceptLoop());
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    try {
      await _listener?.close();
    } catch (_) {}

    for (final client in _clients.values.toList()) {
      try {
        await _sendString(client, PacketType.disconnect, 'تم إيقاف الخادم من قبل المسؤول.');
        client.close();
      } catch (_) {}
    }

    _clients.clear();
    _log('WARN', 'SERVER', 'تم إيقاف الخادم وإغلاق جميع المقابس النشطة.');
    onStateChanged?.call(false);
  }

  Future<void> _acceptLoop() async {
    final listener = _listener;
    if (listener == null) return;
    await for (final socket in listener) {
      unawaited(_handleClient(socket));
    }
  }

  Future<void> _handleClient(Socket socket) async {
    ClientSession? session;
    try {
      session = ClientSession(socket);
      final endpoint = session.remoteEndpoint;
      _log('SOCKET', endpoint, 'تم إنشاء اتصال سوكيت جديد (TCP Handshake مكتمل)');

      final decoder = PacketDecoder();
      var registered = false;

      await for (final chunk in socket) {
        decoder.write(chunk);
        while (true) {
          final packet = decoder.tryDecode();
          if (packet == null) break;
          _recordMetrics(packet.payload.length + PacketProtocol.headerSize);
          if (!registered) {
            final accepted = await _tryHandshake(session, packet);
            if (!accepted) return;
            registered = true;
            continue;
          }
          await _processPacket(session, packet);
        }
      }
    } catch (e) {
      if (_isRunning && session != null) {
        _log('WARN',
            session.username ?? session.remoteEndpoint,
            'انقطع الاتصال: $e');
      }
    } finally {
      if (session != null) {
        await _cleanupSession(session);
      }
    }
  }

  Future<bool> _tryHandshake(ClientSession session, NetworkPacket packet) async {
    if (packet.type != PacketType.connectRequest) {
      await _sendString(session, PacketType.connectResponse, 'REJECT:بروتوكول غير صالح');
      session.close();
      return false;
    }

    final requestedUsername = packet.payloadAsUtf8.trim();
    if (requestedUsername.isEmpty) {
      await _sendString(session, PacketType.connectResponse, 'REJECT:اسم المستخدم فارغ');
      session.close();
      return false;
    }

    final userBan = _bannedEntries[requestedUsername];
    BannedEntry? activeBan = (userBan != null && userBan.isActive) ? userBan : null;
    if (activeBan != null) {
      final mins = max(1, (activeBan.remainingTime.inSeconds / 60).ceil());
      final banMsg = 'REJECT:لقد تم طردك بسبب: ${activeBan.reason} - يمكنك معاودة الاتصال بعد $mins دقائق.';
      await _sendString(session, PacketType.connectResponse, banMsg);
      _log('BAN', session.remoteEndpoint, 'محاولة اتصال مرفوضة لعميل محظور [$requestedUsername] - المتبقي: $mins دقائق');
      session.close();
      return false;
    }

    if (_containsClient(requestedUsername)) {
      await _sendString(session, PacketType.connectResponse, 'REJECT:اسم المستخدم مستخدم مسبقاً');
      _log('WARN', session.remoteEndpoint, "رفض الاتصال: الاسم '$requestedUsername' مستخدم حالياً");
      session.close();
      return false;
    }

    if (approveConnection != null) {
      _log('AUTH', session.remoteEndpoint, 'طلب اتصال وارد من [$requestedUsername]. بانتظار قرار المدير...');
      final isApproved = await approveConnection!(requestedUsername, session);
      if (!isApproved) {
        await _sendString(session, PacketType.connectResponse, 'REJECT:تم رفض طلب اتصالك من قبل مدير الخادم.');
        _log('WARN', session.remoteEndpoint, 'تم رفض طلب اتصال العميل [$requestedUsername] من قبل المدير.');
        session.close();
        return false;
      }
    }

    session.username = requestedUsername;
    _clients[requestedUsername] = session;

    try {
      await _db?.upsertClient(session.username!, session.remoteAddress.address, session.remotePort);
      await _db?.startSession(session.username!, session.remoteAddress.address, session.remotePort);
    } catch (_) {}

    await _sendString(session, PacketType.connectResponse, 'OK:مرحباً بك في خادم المحادثة');
    _log('AUTH', session.username!, 'تمت الموافقة وقبول العميل بنجاح من IP: ${session.remoteAddress.address} ومنفذ: ${session.remotePort}');

    onClientJoined?.call(session);
    await broadcastUserList();
    return true;
  }

  Future<void> _cleanupSession(ClientSession session) async {
    if (session.username == null || session.username!.isEmpty) {
      session.close();
      return;
    }

    _clients.remove(session.username);
    onClientLeft?.call(session);
    _log('DISCONNECT', session.username!, 'غادر العميل الشبكة [${session.remoteEndpoint}]');
    unawaited(broadcastUserList());

    try {
      await _db?.setClientOffline(session.username!);
      await _db?.endSession(session.username!);
    } catch (_) {}

    final usernameLower = session.username!.toLowerCase();
    for (final key in _activeCallStartTimes.keys.toList()) {
      if (key.toLowerCase().contains(usernameLower)) {
        final startTime = _activeCallStartTimes.remove(key);
        if (startTime != null) {
          final durationText = formatDurationMmSs(startTime, DateTime.now());
          _log('CALL', key, '⏹️ إنهاء المكالمة لانقطاع اتصال العميل (البدء: ${_formatTimeHhMmSs(startTime)} | الانتهاء: ${_formatTimeHhMmSs(DateTime.now())} | المدة: $durationText)');
        }
      }
    }

    session.close();
  }

  String _formatTimeHhMmSs(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Future<void> _processPacket(ClientSession senderSession, NetworkPacket packet) async {
    switch (packet.type) {
      case PacketType.publicMessage:
        {
          final msg = ChatMessageModel.deserialize(packet.payload);
          msg.sender = senderSession.username!;
          msg.timestamp = DateTime.now();

          try {
            await _db?.saveChatMessage(
              msg.sender,
              'الجميع (عامة)',
              msg.message,
              msg.isEncrypted,
              'عامة',
              senderSession.remoteAddress.address,
            );
          } catch (_) {}

          final broadcastData = msg.serialize();
          final logText = msg.isEncrypted ? '[🔒 مشفرة AES-256]: "${msg.message}"' : '"${msg.message}"';
          _log('CHAT_PUB', senderSession.username!, 'رسالة عامة $logText (${packet.payload.length} بايت)');

          await broadcastPacket(PacketType.publicMessage, broadcastData);
        }

      case PacketType.privateMessage:
        {
          final msg = ChatMessageModel.deserialize(packet.payload);
          msg.sender = senderSession.username!;
          msg.timestamp = DateTime.now();

          try {
            await _db?.saveChatMessage(
              msg.sender,
              msg.recipient,
              msg.message,
              msg.isEncrypted,
              'خاصة',
              senderSession.remoteAddress.address,
            );
          } catch (_) {}

          final logText = msg.isEncrypted ? '[🔒 مشفرة AES-256]: "${msg.message}"' : '"${msg.message}"';
          _log('CHAT_PRIV', '${senderSession.username} -> ${msg.recipient}', 'رسالة خاصة $logText (${packet.payload.length} بايت)');

          final target = _findClient(msg.recipient);
          if (target != null) {
            final privData = msg.serialize();
            await _sendPacket(target, PacketType.privateMessage, privData);
            await _sendPacket(senderSession, PacketType.privateMessage, privData);
          } else {
            final systemMsg = ChatMessageModel(
              sender: 'SYSTEM',
              recipient: senderSession.username!,
              message: "المستخدم '${msg.recipient}' غير متصل حالياً.",
              timestamp: DateTime.now(),
            );
            await _sendPacket(senderSession, PacketType.privateMessage, systemMsg.serialize());
          }
        }

      case PacketType.fileMetadata:
        {
          final header = FileHeaderModel.deserialize(packet.payload);
          header.sender = senderSession.username!;

          try {
            await _db?.logFileTransfer(
              header.transferId,
              header.sender,
              header.recipient,
              header.fileName,
              header.fileSize,
              'قيد النقل',
            );
          } catch (_) {}

          _log('FILE_META', senderSession.username!, 'بدء إرسال ملف: "${header.fileName}" بحجم: ${formatBytes(header.fileSize)} إلى: ${header.recipient.isEmpty ? 'الجميع' : header.recipient}');

          // نحفظ وجهة النقل لتوجيه القطع لاحقاً
          _fileTransferTargets[header.transferId] = header.isPrivate ? header.recipient : '';

          final headerData = header.serialize();
          if (header.isPrivate) {
            final target = _findClient(header.recipient);
            if (target != null) {
              await _sendPacket(target, PacketType.fileMetadata, headerData);
            }
          } else {
            await broadcastPacket(PacketType.fileMetadata, headerData, excludeUsername: senderSession.username!);
          }
        }

      case PacketType.fileChunk:
        {
          // نُوجّه القطعة للمستقبل الصحيح حسب نوع النقل المحفوظ
          final chunk = FileChunkModel.deserialize(packet.payload);
          final recipient = _fileTransferTargets[chunk.transferId] ?? '';
          if (recipient.isNotEmpty) {
            // نقل خاص — للمستقبل فقط
            final target = _findClient(recipient);
            if (target != null) {
              await _sendPacket(target, PacketType.fileChunk, packet.payload);
            }
          } else {
            // نقل عام — للجميع ما عدا المرسل
            await broadcastPacket(PacketType.fileChunk, packet.payload,
                excludeUsername: senderSession.username!);
          }
        }

      case PacketType.fileComplete:
        {
          final transferId = utf8.decode(packet.payload, allowMalformed: true);
          final recipient = _fileTransferTargets.remove(transferId) ?? '';
          _log('FILE_DONE', senderSession.username!, 'اكتمل نقل الملف (transferId: $transferId).');
          if (recipient.isNotEmpty) {
            // نقل خاص — إشعار الاكتمال للمستقبل فقط
            final target = _findClient(recipient);
            if (target != null) {
              await _sendPacket(target, PacketType.fileComplete, packet.payload);
            }
          } else {
            await broadcastPacket(PacketType.fileComplete, packet.payload,
                excludeUsername: senderSession.username!);
          }
        }

      case PacketType.voiceMessage:
        {
          final voice = VoiceMessageModel.deserialize(packet.payload);
          voice.sender = senderSession.username!;
          voice.timestamp = DateTime.now();

          final voiceData = voice.serialize();
          _log('VOICE', senderSession.username!, 'رسالة صوتية (${voice.durationSeconds} ثانية) إلى: ${voice.isPrivate ? voice.recipient : 'الجميع'}');

          if (voice.isPrivate) {
            final target = _findClient(voice.recipient);
            if (target != null) {
              await _sendPacket(target, PacketType.voiceMessage, voiceData);
              await _sendPacket(senderSession, PacketType.voiceMessage, voiceData);
            }
          } else {
            await broadcastPacket(PacketType.voiceMessage, voiceData);
          }
        }

      case PacketType.videoFrame:
        {
          final vframe = VideoFrameModel.deserialize(packet.payload);
          vframe.sender = senderSession.username!;
          vframe.timestamp = DateTime.now();

          final frameData = vframe.serialize();
          if (vframe.isPrivate) {
            final target = _findClient(vframe.recipient);
            if (target != null) {
              await _sendPacket(target, PacketType.videoFrame, frameData);
            }
          } else {
            await broadcastPacket(PacketType.videoFrame, frameData, excludeUsername: senderSession.username!);
          }
        }

      case PacketType.callSignal:
        {
          final signal = CallSignalModel.deserialize(packet.payload);
          signal.sender = senderSession.username!;

          String callKey;
          if (signal.recipient.isEmpty || signal.recipient.startsWith('الجميع')) {
            callKey = '${signal.sender} (بث عام)';
          } else {
            final compare = signal.sender.toLowerCase().compareTo(signal.recipient.toLowerCase());
            callKey = compare < 0 ? '${signal.sender} <-> ${signal.recipient}' : '${signal.recipient} <-> ${signal.sender}';
          }

          if (signal.signalType == 'START') {
            if (signal.recipient.isNotEmpty && !_containsClient(signal.recipient)) {
              final offlineSignal = CallSignalModel(
                sender: signal.recipient,
                recipient: senderSession.username!,
                signalType: 'OFFLINE',
              );
              await _sendPacket(senderSession, PacketType.callSignal, offlineSignal.serialize());
              _log('CALL', senderSession.username!, "⚠️ محاولة اتصال بمستخدم غير متصل: '${signal.recipient}'");
            } else if (!_activeCallStartTimes.containsKey(callKey)) {
              _activeCallStartTimes[callKey] = DateTime.now();
              _log('CALL', callKey, '📞 طلب بدء مكالمة (المتصل: ${signal.sender} -> ${signal.recipient})');
            }
          } else if (signal.signalType == 'ACCEPT') {
            _log('CALL', callKey, '🟢 تمت الموافقة على المكالمة بين ${signal.sender} و ${signal.recipient}');
          } else if (signal.signalType == 'END' ||
              signal.signalType == 'REJECT' ||
              signal.signalType == 'BUSY' ||
              signal.signalType == 'CANCEL') {
            final startTime = _activeCallStartTimes.remove(callKey);
            if (startTime != null) {
              final durationText = formatDurationMmSs(startTime, DateTime.now());
              _log('CALL', callKey, '⏹️ إنهاء/إلغاء المكالمة [${signal.signalType}] (البدء: ${_formatTimeHhMmSs(startTime)} | الانتهاء: ${_formatTimeHhMmSs(DateTime.now())} | المدة: $durationText)');
            }
          }

          if (signal.recipient.isNotEmpty) {
            final target = _findClient(signal.recipient);
            if (target != null) {
              await _sendPacket(target, PacketType.callSignal, signal.serialize());
            }
          }
        }

      case PacketType.disconnect:
        {
          _log('INFO', senderSession.username!, 'أرسل العميل طلب إنهاء الاتصال الودي.');
        }

      case PacketType.connectRequest:
      case PacketType.connectResponse:
      case PacketType.userListUpdate:
      case PacketType.kickNotice:
        {
          // لا تحتاج معالجة من الخادم
        }
    }
  }

  Future<void> broadcastPacket(
    PacketType type,
    List<int> payload, {
    String? excludeUsername,
  }) async {
    final futures = <Future<void>>[];
    for (final client in _clients.values) {
      if (excludeUsername != null &&
          excludeUsername.isNotEmpty &&
          client.username != null &&
          client.username!.toLowerCase() == excludeUsername.toLowerCase()) {
        continue;
      }
      futures.add(_sendPacket(client, type, payload));
    }
    await Future.wait(futures);
  }

  Future<void> broadcastUserList() async {
    final users = _clients.values.map((s) => s.username!).toList();
    final payload = utf8.encode(users.join(','));
    await broadcastPacket(PacketType.userListUpdate, payload);
  }

  Future<bool> kickClient(String username, String reason, {int banMinutes = 5}) async {
    final session = _findClient(username);
    if (session == null) return false;

    final banUntil = DateTime.now().add(Duration(minutes: banMinutes));
    _bannedEntries[username] = BannedEntry(
      username: username,
      ipAddress: session.remoteAddress.address,
      reason: reason,
      bannedAt: DateTime.now(),
      bannedUntil: banUntil,
    );

    try {
      await _db?.recordBan(username, reason, banMinutes);
      await _db?.endSession(username, 'طرد: $reason');
    } catch (_) {}

    final kickMsg = 'لقد تم طردك بسبب: $reason\nيمكنك معاودة الاتصال بعد $banMinutes دقائق.';
    try {
      await _sendString(session, PacketType.kickNotice, kickMsg);
      session.close();
    } catch (_) {}

    _log('KICK', 'ADMIN', 'تم طرد وحظر العميل \'$username\' [${session.remoteAddress.address}] لمدة $banMinutes دقائق. السبب: $reason');
    return true;
  }

  ClientSession? _findClient(String username) {
    for (final client in _clients.values) {
      if (client.username != null && client.username!.toLowerCase() == username.toLowerCase()) {
        return client;
      }
    }
    return null;
  }

  bool _containsClient(String username) {
    for (final client in _clients.values) {
      if (client.username != null && client.username!.toLowerCase() == username.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  void _recordMetrics(int bytes) {
    _totalBytes += bytes;
    _totalPackets++;
    onStatsUpdated?.call(_totalBytes, _totalPackets);
  }

  Future<void> _sendPacket(ClientSession session, PacketType type, List<int> payload) {
    return session.queueSend(framePacket(type, payload));
  }

  Future<void> _sendString(ClientSession session, PacketType type, String text) {
    final payload = text.isEmpty ? <int>[] : utf8.encode(text);
    return _sendPacket(session, type, payload);
  }

  void _log(String type, String source, String message) {
    onLog?.call(type, source, message);
    unawaited(_writeActivityLog(type, source, message));
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get _activityLogFileName {
    final now = DateTime.now();
    return 'Activity_${now.year}-${_two(now.month)}-${_two(now.day)}.log';
  }

  Future<void> _writeActivityLog(
      String type, String source, String message) async {
    try {
      final now = DateTime.now();
      final line = '[${_formatTimeHhMmSs(now)}] [$type] [$source] $message\n';
      final file = File('logs/$_activityLogFileName');
      await file.parent.create(recursive: true);
      await file.writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _logLanIps(int serverPort) async {
    try {
      final lanIps = await listLanIpAddresses();
      if (lanIps.isNotEmpty) {
        _log('INFO', 'NETWORK', '🌐 عناوين IP المتاحة للاتصال من أجهزة أخرى في الشبكة: ${lanIps.join(' | ')} (المنفذ: $serverPort)');
      }
    } catch (_) {}
  }

  static Future<List<String>> listLanIpAddresses() async {
    final result = <String>[];
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final ni in interfaces) {
        final nameLower = ni.name.toLowerCase();
        if (nameLower.contains('vmware') || nameLower.contains('virtual')) continue;
        for (final addr in ni.addresses) {
          if (addr.isLoopback || addr.address.startsWith('169.254.')) continue;
          result.add(addr.address);
        }
      }
    } catch (_) {}
    return result;
  }

  static Future<String> bestLanIpString() async {
    try {
      final ips = await listLanIpAddresses();
      if (ips.isNotEmpty) return ips.first;
    } catch (_) {}
    return '192.168.128.243';
  }

  static String formatBytes(int bytes) {
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
}