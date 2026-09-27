import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:client_app/async_client.dart';
import 'package:client_app/screens/demo_screens.dart';
import 'package:client_app/services/hardware_services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClientApp());
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'عميل المحادثة الشبكي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: ConnectionScreen(),
      ),
    );
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _ipController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8989');
  final _nameController = TextEditingController();
  bool _connecting = false;
  bool _lastAttemptFailed = false;
  String _status = 'جاهز للاتصال بالخادم عبر السوكيت.';

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLastConnection());
  }

  Future<void> _restoreLastConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString('last_ip');
      final port = prefs.getInt('last_port');
      final name = prefs.getString('last_name');
      if (!mounted) return;
      setState(() {
        if (ip != null && ip.isNotEmpty) _ipController.text = ip;
        if (port != null && port > 0) _portController.text = '$port';
        if (name != null && name.isNotEmpty) _nameController.text = name;
      });
    } catch (_) {
      // بيئة اختبار دون مكون التخزين المحلي — نبقي القيم الافتراضية.
    }
  }

  String normalizeAddress(String input) {
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

  Future<void> _connect() async {
    final ip = normalizeAddress(_ipController.text);
    final name = _nameController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || name.isEmpty) {
      _showWarning('يرجى إدخال عنوان IP واسم المستخدم بشكل صحيح.');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      _showWarning('يرجى إدخال رقم منفذ صالح بين 1 و 65535');
      return;
    }

    setState(() {
      _connecting = true;
      _lastAttemptFailed = false;
      _status = 'جاري إرسال طلب الاتصال للخادم ($ip:$port)... بانتظار موافقة المدير.';
    });

    final client = AsyncClient();
    String? failReason;
    client.onConnectionFailed = (error) async => failReason = error;
    client.onDisconnected = (_) async {};

    await client.connect(ip, port, name);

    if (!mounted) return;
    if (client.isConnected) {
      unawaited(_saveLastConnection(ip, port, name));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: ChatScreen(client: client),
          ),
        ),
      );
    } else {
      setState(() {
        _connecting = false;
        _lastAttemptFailed = true;
        _status = 'فشل الاتصال: $failReason';
      });
      _showConnectionWarning(failReason ?? 'تعذر الاتصال');
    }
  }

  Future<void> _saveLastConnection(String ip, int port, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_ip', ip);
      await prefs.setInt('last_port', port);
      await prefs.setString('last_name', name);
    } catch (_) {
      // في بيئات الاختبار قد لا يتوفر مكون التخزين المحلي — نتجاهل الخطأ بصمت.
    }
  }

  void _showWarning(String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تنبيه'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  void _showConnectionWarning(String error) {
    final low = error.toLowerCase();
    final String message;
    if (low.contains('refused') || low.contains('رفض') || low.contains('aborted')) {
      message = 'تعذر الوصول إلى الخادم: تم رفض الاتصال.\n\n'
          'تأكد من أن برنامج الخادم قيد التشغيل، وأن المنفذ صحيح، ثم اضغط «إعادة محاولة».';
    } else if (low.contains('timeout') || low.contains('انتهت المهلة')) {
      message = 'انتهت مهلة انتظار موافقة المدير.\n\n'
          'اضغط «اتصال» مرة ثانية ثم في نفس الوقت اضغط «نعم» في نافذة الخادم على الكمبيوتر خلال 60 ثانية.';
    } else if (low.contains('lookup') || low.contains('resolve') ||
        low.contains('تعذر التعرف')) {
      message = 'تعذر تحديد عنوان الخادم (فشل تحليل العنوان).\n\n'
          'تحقق من كتابة عنوان IP بشكل صحيح (مثال: 192.168.1.10).';
    } else {
      message = 'تعذر الاتصال بالخادم:\n$error\n\n'
          'تحقق من أن الخادم يعمل وأن العنوان صحيح (127.0.0.1 عبر كابل USB، أو عنوان IP الحقيقي من شبكة أخرى).';
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تنبيه اتصال'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.forum, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  'عميل المحادثة الشبكي',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'ترجمة مشروع C# إلى Flutter',
                  style: TextStyle(color: Colors.grey.shade400),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان IP:',
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: 'رقم المنفذ:',
                          prefixIcon: Icon(Icons.settings_ethernet),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم:',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _connecting ? null : _connect,
                    icon: _connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(_connecting ? 'جاري الاتصال...' : 'اتصال بالخادم'),
                  ),
                ),
                if (_lastAttemptFailed && !_connecting)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _connect,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة محاولة الاتصال'),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScreensGalleryScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('معرض الواجهات (للعرض)'),
                ),
                const SizedBox(height: 10),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ChatMode { hub, public, private }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.client});

  final AsyncClient client;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final AsyncClient _client = widget.client;
  _ChatMode _mode = _ChatMode.hub;

  final List<ChatMessageModel> _publicMessages = [];
  final List<ChatMessageModel> _privateMessages = [];
  final List<String> _users = [];
  final List<VoiceEntry> _publicVoices = [];
  final List<VoiceEntry> _privateVoices = [];
  final List<FileEntry> _fileEntries = [];

  final Map<String, UserProfile> _userProfiles = {};

  // خلفية البروفايل المشتركة (تظهر للجميع) — تُحفظ محلياً في العميل
  String? _globalProfileCoverBase64;
  String? _globalProfileAvatarBase64;

  final TextEditingController _messageController = TextEditingController();
  String? _privateTarget;
  bool _inThread = false;
  bool _encrypted = false;
  String _status = '';
  String _localUsername = '';
  bool _isRecordingVoice = false;

  // إعدادات الواجهة (تأثير محلي فقط)

  // المكالمة والفيديو
  bool _callActive = false;
  bool _isRinging = false;
  String? _currentCallPartner;
  Uint8List? _remoteFrame;
  Uint8List? _localFrame;
  final VoiceNoteRecorder _voiceRecorder = VoiceNoteRecorder();
  CallAudioRecorder? _callAudioRecorder;
  CallAudioPlayer? _callAudioPlayer;
  CameraStreamSource? _cameraSource;
  final AudioPlayer _voicePlayer = AudioPlayer();

  // شريط تشغيل الصوت (VoicePlayBar)
  VoiceEntry? _activeVoiceBarEntry;
  bool _voiceBarPlaying = false;

  // كتم الميكروفون أثناء المكالمة
  bool _callMuted = false;

  final ScrollController _publicScroll = ScrollController();
  final ScrollController _privateScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _localUsername = _client.username ?? '';
    _client.onUserListUpdated = _onUserList;
    _client.onPublicMessage = _onPublicMessage;
    _client.onPrivateMessage = _onPrivateMessage;
    _client.onVoiceMessage = _onVoiceMessage;
    _client.onVideoFrame = _onVideoFrame;
    _client.onCallSignal = _onCallSignal;
    _client.onIncomingFileStarted = _onFileStarted;
    _client.onIncomingFileProgress = _onFileProgress;
    _client.onIncomingFileCompleted = _onFileCompleted;
    _client.onKicked = _onKicked;
    _client.onDisconnected = _onDisconnected;
    if (_client.currentUsers.isNotEmpty) {
      _onUserList(_client.currentUsers);
    }
    _setStatus('متصل بالخادم: ${_client.serverIp}:${_client.serverPort} '
        'باسم [$_localUsername]');
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  void _scrollToBottom(bool private) {
    final c = private ? _privateScroll : _publicScroll;
    if (c.hasClients) {
      c.animateTo(c.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  Future<void> _onUserList(List<String> users) async {
    if (!mounted) return;
    setState(() {
      _users
        ..clear()
        ..addAll(users.reversed);
      for (final u in _users) {
        final k = u.toLowerCase();
        if (!_userProfiles.containsKey(k)) {
          _userProfiles[k] = UserProfile(username: u);
        }
      }
    });
  }

  Future<void> _onPublicMessage(ChatMessageModel msg) async {
    if (!mounted) return;
    setState(() => _publicMessages.add(msg));
    _scrollToBottom(false);
  }

  Future<void> _onPrivateMessage(ChatMessageModel msg) async {
    if (!mounted) return;
    setState(() => _privateMessages.add(msg));
    _scrollToBottom(true);
  }

  Future<void> _onVoiceMessage(VoiceMessageModel voice) async {
    if (!mounted) return;
    setState(() {
      final entry = VoiceEntry(voice);
      if (voice.isPrivate) {
        _privateVoices.add(entry);
      } else {
        _publicVoices.add(entry);
      }
      // يفتح شريط التشغيل تلقائياً عند استلام رسالة صوتية جديدة
      _activeVoiceBarEntry = entry;
      _voiceBarPlaying = false;
    });
    if (voice.isPrivate) _scrollToBottom(true);
  }

  Future<void> _onVideoFrame(VideoFrameModel frame) async {
    final audio = frame.audioData;
    if (audio.isNotEmpty) {
      await _callAudioPlayer?.playChunk(Uint8List.fromList(audio));
    }
    if (!mounted || frame.frameData.isEmpty) return;
    setState(() => _remoteFrame = Uint8List.fromList(frame.frameData));
  }

  Future<void> _onFileStarted(FileHeaderModel header) async {
    if (!mounted) return;
    setState(() {
      _fileEntries.add(FileEntry(
        transferId: header.transferId,
        fileName: header.fileName,
        fileSize: header.fileSize,
        sender: header.sender,
      ));
    });
    _setStatus('جاري استقبال ملف: ${header.fileName} '
        '(${_formatBytes(header.fileSize)}) من [${header.sender}]...');
  }

  Future<void> _onFileProgress(String id, int current, int total) async {
    final i = _fileEntries.indexWhere((e) => e.transferId == id);
    if (i >= 0 && mounted) {
      setState(() {
        _fileEntries[i].current = current;
        _fileEntries[i].total = total;
      });
    }
  }

  Future<void> _onFileCompleted(String id, String savedPath) async {
    final i = _fileEntries.indexWhere((e) => e.transferId == id);
    if (i >= 0 && mounted) {
      setState(() {
        _fileEntries[i].savedPath = savedPath;
        _fileEntries[i].done = true;
      });
      _setStatus('✓ تم استلام الملف وحفظه بنجاح: ${p.basename(savedPath)}');
    }
  }

  Future<void> _onKicked(String reason) async {
    _callAudioPlayer?.stop();
    if (mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('إشعار طرد وحظر'),
          content: Text('⚠️ تم طردك وحظرك من الخادم بواسطة المسؤول!\n\n'
              'التفاصيل: $reason'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const Directionality(
            textDirection: TextDirection.rtl,
            child: ConnectionScreen(),
          ),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _onDisconnected(String reason) async {
    if (_callActive || _isRinging) {
      await _endVideoCall(notifyOther: false);
    } else {
      _callAudioPlayer?.stop();
    }
    if (mounted) _setStatus('تم قطع الاتصال: $reason');
  }

  Future<void> _send(bool private) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (private && !_canSendPrivate) {
      _showSnack('يرجى اختيار مستخدم من القائمة لمراسلته بالخاص.');
      return;
    }
    final recipient = private ? _privateTarget! : '';
    if (private && recipient == _localUsername) {
      _showSnack('لا يمكنك إرسال رسالة خاصة إلى نفسك!');
      return;
    }

    if (private) {
      await _client.sendPrivateMessage(recipient, text, isEncrypted: _encrypted);
    } else {
      await _client.sendPublicMessage(text, isEncrypted: _encrypted);
    }
    _messageController.clear();
  }

  bool get _canSendPrivate =>
      _privateTarget != null && _users.contains(_privateTarget);

  Future<void> _pickAndSendFile() async {
    final selected = await openFile();
    if (selected == null) return;
    final path = selected.path;
    final length = await selected.length();
    if (length == 0) {
      _showSnack('الملف المحدد فارغ (0 بايت). لا يمكن إرسال ملف فارغ دون محتوى.');
      return;
    }
    final receiver = _privateTarget ?? '';
    if (receiver == _localUsername) {
      _showSnack('لا يمكنك إرسال ملف إلى نفسك!');
      return;
    }
    try {
      await _client.sendFile(path, receiver,
          onProgress: (percent) {
        _setStatus('جاري إرسال الملف... $percent%');
      });
      _setStatus('تم إرسال الملف بالكامل عبر الشبكة!');
    } catch (e) {
      _showSnack('حدث خطأ أثناء نقل الملف: $e');
    }
  }

  Future<void> _toggleVoiceNote() async {
    if (!_client.isConnected) return;
    if (!_isRecordingVoice) {
      try {
        await _voiceRecorder.start();
        setState(() => _isRecordingVoice = true);
        _setStatus('🔴 جاري تسجيل الصوت من المايكروفون...');
      } catch (e) {
        _showSnack('خطأ في المايك: $e');
      }
    } else {
      setState(() => _isRecordingVoice = false);
      _setStatus('تم إنهاء التسجيل، جاري إرسال الرسالة الصوتية...');
      final result = await _voiceRecorder.stop();
      if (result != null && result.wavBytes.isNotEmpty) {
        final recipient = _privateTarget ?? '';
        if (_privateTarget != null && recipient == _localUsername) {
          _showSnack('لا يمكنك إرسال صوت إلى نفسك');
          return;
        }
        await _client.sendVoiceMessage(recipient, result.wavBytes, result.duration);
        _setStatus('✓ تم إرسال الرسالة الصوتية بنجاح.');
      } else {
        _setStatus('⚠️ لم يتم التقاط أي صوت من المايكروفون (التسجيل فارغ).');
      }
    }
  }

  Future<void> _playVoice(VoiceEntry entry) async {
    try {
      await _voicePlayer.stop();
      await _voicePlayer.dispose();
    } catch (_) {}
    final player = AudioPlayer();
    _playingPlayer = player;
    try {
      await player.play(BytesSource(Uint8List.fromList(entry.voice.audioData)));
      player.onPlayerComplete.listen((_) {
        player.dispose();
        _playingPlayer = null;
      });
    } catch (_) {}
  }

  AudioPlayer? _playingPlayer;

  Future<void> _openDownloadsFolder() async {
    try {
      final dir = _client.downloadDirectory;
      if (!Directory(dir).existsSync()) Directory(dir).createSync(recursive: true);
      await Process.run('explorer.exe', [dir]);
    } catch (_) {}
  }

  // ================ مكالمات الفيديو والصوت ================

  Future<void> _startVideoCall() async {
    if (!_client.isConnected) {
      _showSnack('يرجى الاتصال بالخادم أولاً لتشغيل مكالمة الفيديو.');
      return;
    }
    if (_callActive || _isRinging) {
      _showSnack('أنت بالفعل في مكالمة حالية أو جاري الاتصال!');
      return;
    }
    final target = _privateTarget;
    if (target == null) {
      _showSnack('يرجى تحديد مستخدم من القائمة أولاً لبدء مكالمة الفيديو معه.');
      return;
    }
    if (target == _localUsername) {
      _showSnack('لا يمكنك بدء مكالمة مع نفسك!');
      return;
    }

    setState(() {
      _isRinging = true;
      _currentCallPartner = target;
    });
    _setStatus('⏳ جاري الاتصال بـ [$target]...');

    final accepted = await _client
        .sendCallSignal(target, 'START')
        .then((_) => _waitForAnswer(target));
    if (!mounted) return;

    if (accepted) {
      await _beginActiveCall(target);
    } else {
      setState(() {
        _isRinging = false;
        _currentCallPartner = null;
      });
      _resetVideo();
    }
  }

  Future<bool> _waitForAnswer(String partner) async {
    final completer = Completer<bool>();
    late void Function(CallSignalModel) original;
    original = _signalHandler;
    _signalHandler = (signal) {
      if (signal.sender != partner) return;
      switch (signal.signalType) {
        case 'ACCEPT':
          if (!completer.isCompleted) completer.complete(true);
          break;
        case 'DECLINE':
          _showSnack('قام [$partner] برفض طلب المكالمة.');
          if (!completer.isCompleted) completer.complete(false);
          break;
        case 'BUSY':
          _showSnack('المستخدم [$partner] مشغول بمكالمة أخرى في الوقت الحالي.');
          if (!completer.isCompleted) completer.complete(false);
          break;
        case 'OFFLINE':
          _showSnack('المستخدم [$partner] غير متصل بالخادم حالياً.');
          if (!completer.isCompleted) completer.complete(false);
          break;
        case 'CANCEL':
        case 'END':
          break;
      }
    };
    final timeout = Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.complete(false);
        _showSnack('لم يقم [$partner] بالرد على طلب المكالمة خلال 30 ثانية.');
      }
    });
    final result = await completer.future;
    unawaited(timeout);
    _signalHandler = original;
    return result;
  }

  Future<void> _beginActiveCall(String partner) async {
    setState(() {
      _isRinging = false;
      _callActive = true;
      _currentCallPartner = partner;
    });
    _callAudioRecorder = CallAudioRecorder();
    await _callAudioRecorder!.start();
    _callAudioPlayer = CallAudioPlayer();
    await _callAudioPlayer!.start();
    _cameraSource = CameraStreamSource();
    _remoteFrame = null;
    unawaited(_subscribeCamera());
    _setStatus('📹 بث مباشر مزدوج (صوت وصورة) إلى [$partner]...');
  }

  Future<void> _subscribeCamera() async {
    await _cameraSource!.start();
    _cameraSource!.frames!.listen((frame) {
      _onLocalFrame(frame);
    });
  }

  Future<void> _onLocalFrame(VideoFrameEmitted frame) async {
    if (!_callActive) return;
    if (mounted && frame.imageBytes.isNotEmpty) {
      setState(() => _localFrame = frame.imageBytes);
    }
    // لا يُرسل صوت الميكروفون إذا كان الصوت مكتوماً
    final audio = _callMuted ? null : _callAudioRecorder?.takePendingChunk();
    if (_client.isConnected) {
      await _client.sendVideoFrame(
          _currentCallPartner ?? '', frame.imageBytes, audio);
    }
  }

  Future<void> _endVideoCall({bool notifyOther = true}) async {
    if (_isRinging && _currentCallPartner != null) {
      await _client.sendCallSignal(_currentCallPartner!, 'CANCEL');
    }
    if (_callActive && notifyOther && _currentCallPartner != null) {
      await _client.sendCallSignal(_currentCallPartner!, 'END');
    }
    final camera = _cameraSource;
    _cameraSource = null;
    await camera?.dispose();
    await _callAudioRecorder?.stop();
    _callAudioRecorder = null;
    await _callAudioPlayer?.stop();
    _callAudioPlayer = null;
    if (mounted) {
      setState(() {
        _callActive = false;
        _isRinging = false;
        _currentCallPartner = null;
        _remoteFrame = null;
        _localFrame = null;
      });
      _resetVideo();
    }
  }

  void _resetVideo() {
    _setStatus('الكاميرا والصوت متوقفان');
  }

  late void Function(CallSignalModel signal) _signalHandler = (signal) {};

  Future<void> _onCallSignal(CallSignalModel signal) async {
    _signalHandler(signal);
    if (!mounted) return;
    switch (signal.signalType) {
      case 'START':
        if (_callActive || _isRinging) {
          await _client.sendCallSignal(signal.sender, 'BUSY');
          break;
        }
        _handleIncomingCall(signal.sender);
        break;
      case 'ACCEPT':
        break;
      case 'END':
        if (_callActive && signal.sender == _currentCallPartner) {
          _showSnack('تم إنهاء المكالمة مع [${signal.sender}].');
          await _endVideoCall(notifyOther: false);
        }
        break;
      case 'CANCEL':
        if (_isRinging && signal.sender == _currentCallPartner) {
          setState(() {
            _isRinging = false;
            _currentCallPartner = null;
          });
          _resetVideo();
        }
        break;
    }
  }

  void _handleIncomingCall(String partner) {
    setState(() {
      _isRinging = true;
      _currentCallPartner = partner;
    });
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('مكالمة فيديو من [$partner]'),
        content: const Text('هل ترغب في قبول المكالمة؟'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _client.sendCallSignal(partner, 'DECLINE');
              setState(() {
                _isRinging = false;
                _currentCallPartner = null;
              });
            },
            child: const Text('رفض', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _client.sendCallSignal(partner, 'ACCEPT');
              await _beginActiveCall(partner);
            },
            child: const Text('قبول'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatBytes(int bytes) {
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
      text = len.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return '$text ${sizes[order]}';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _publicScroll.dispose();
    _privateScroll.dispose();
    _voiceRecorder.dispose();
    _playingPlayer?.dispose();
    _voicePlayer.dispose();
    _cameraSource?.dispose();
    _callAudioRecorder?.dispose();
    _callAudioPlayer?.dispose();
    _client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHub = _mode == _ChatMode.hub;
    final isPrivate = _mode == _ChatMode.private;
    final String title;
    if (isHub) {
      title = 'عميل المحادثة - $_localUsername';
    } else if (isPrivate) {
      title = 'المحادثة الخاصة';
    } else {
      title = 'المحادثة العامة';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
          actions: [
            if (!isHub)
              IconButton(
                tooltip: 'الشاشة الرئيسية',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => setState(() => _mode = _ChatMode.hub),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'القائمة',
              onSelected: (v) {
                if (v == 'profile') {
                  _showProfileDialog();
                } else if (v == 'cover') {
                  _pickAndSetGlobalProfileCover();
                } else if (v == 'avatar') {
                  _pickAndSetGlobalProfileAvatar();
                } else if (v == 'gallery') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScreensGalleryScreen(),
                    ),
                  );
                } else if (v == 'about') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WelcomeScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'profile', child: Text('الملف الشخصي')),
                PopupMenuItem(value: 'cover', child: Text('تغيير خلفية البروفايل')),
                PopupMenuItem(value: 'avatar', child: Text('تغيير صورة البروفايل')),
                PopupMenuItem(value: 'gallery', child: Text('معرض الواجهات')),
                PopupMenuItem(value: 'about', child: Text('عن التطبيق')),
              ],
            ),
            if (_callActive || _isRinging)
              TextButton.icon(
                onPressed: () => _endVideoCall(),
                icon: const Icon(Icons.call_end, color: Colors.white),
                label: const Text('إنهاء المكالمة'),
              ),
            if (_callActive)
              IconButton(
                tooltip: _callMuted ? 'تشغيل الميكروفون' : 'كتم الميكروفون',
                icon: Icon(
                  _callMuted ? Icons.mic_off : Icons.mic,
                  color: _callMuted ? Colors.red : Colors.white,
                ),
                onPressed: () => setState(() => _callMuted = !_callMuted),
              ),
            if (!_callActive && !_isRinging)
              TextButton.icon(
                onPressed: _startVideoCall,
                icon: const Icon(Icons.videocam, color: Colors.white),
                label: const Text('مكالمة فيديو'),
              ),
          ],
      ),
      body: Column(
        children: [
          if ((_callActive || _isRinging) && _currentCallPartner != null)
            _buildVideoPanel(),
          Expanded(child: _buildMainRow()),
          if (_activeVoiceBarEntry != null) _buildVoicePlayBar(),
          if (!isHub && (!isPrivate || _inThread)) _buildInputBar(),
          _buildStatusBar(),
        ],
      ),
    );
  }

  // ─────────────────────── شريط VoicePlayBar ───────────────────────
  Widget _buildVoicePlayBar() {
    final entry = _activeVoiceBarEntry!;
    final sender = entry.voice.sender;
    final duration = entry.voice.durationSeconds;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 58,
      decoration: const BoxDecoration(
        color: Color(0xFF0D2B1D),
        border: Border(
          top: BorderSide(color: Color(0xFF2ECC71), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // أيقونة موجة صوت
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.graphic_eq, color: Color(0xFF2ECC71), size: 28),
          ),
          // معلومات الرسالة الصوتية
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔊 رسالة صوتية من [$sender]',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  'المدة: $duration ثانية',
                  style: const TextStyle(
                      color: Color(0xFFA7F3D0), fontSize: 11),
                ),
              ],
            ),
          ),
          // زر تشغيل / إيقاف
          IconButton(
            tooltip: _voiceBarPlaying ? 'إيقاف' : 'تشغيل الصوت',
            icon: Icon(
              _voiceBarPlaying ? Icons.stop_circle : Icons.play_circle_filled,
              color: const Color(0xFF2ECC71),
              size: 34,
            ),
            onPressed: () async {
              if (_voiceBarPlaying) {
                await _voicePlayer.stop();
                setState(() => _voiceBarPlaying = false);
              } else {
                setState(() => _voiceBarPlaying = true);
                await _playVoice(entry);
                _voicePlayer.onPlayerComplete.listen((_) {
                  if (mounted) setState(() => _voiceBarPlaying = false);
                });
              }
            },
          ),
          // زر إغلاق الشريط
          IconButton(
            tooltip: 'إغلاق الشريط',
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            onPressed: () async {
              await _voicePlayer.stop();
              setState(() {
                _activeVoiceBarEntry = null;
                _voiceBarPlaying = false;
              });
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────

  Widget _buildVideoPanel() {
    return Container(
      height: 190,
      padding: const EdgeInsets.all(8),
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
            child: _remoteFrame == null
                ? _videoPlaceholder('فيديو الطرف الآخر (Remote Stream)')
                : Image.memory(_remoteFrame!, fit: BoxFit.contain),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 160,
            child: _localFrame == null
                ? _videoPlaceholder('معاينة الكاميرا المحلية')
                : Image.memory(_localFrame!, fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }

  Widget _videoPlaceholder(String label) {
    return Container(
      color: const Color(0xFF1E293B),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 34, color: Colors.grey),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMainRow() {
    switch (_mode) {
      case _ChatMode.public:
        return _buildPublicScreen();
      case _ChatMode.private:
        return _buildPrivateScreen();
      case _ChatMode.hub:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 220,
              child: _buildUsersPanel(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildHubCenter()),
          ],
        );
    }
  }

  Widget _buildHubCenter() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('المحادثات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('اختر نوع المحادثة للبدء',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          const SizedBox(height: 24),
          _buildChatCard(
            icon: Icons.forum_outlined,
            title: 'المحادثة العامة',
            subtitle: 'رسائل عامة تصل إلى جميع المتصلين',
            accent: const Color(0xFF1E88E5),
            onTap: () => setState(() => _mode = _ChatMode.public),
          ),
          const SizedBox(height: 16),
          _buildChatCard(
            icon: Icons.lock_outline,
            title: 'المحادثة الخاصة',
            subtitle: 'مراسلة مستخدم محدد بالسر',
            accent: const Color(0xFF2ECC71),
            onTap: () => setState(() => _mode = _ChatMode.private),
          ),
          const SizedBox(height: 16),
          _buildChatCard(
            icon: Icons.grid_view_rounded,
            title: 'المعرض والواجهات',
            subtitle: 'عرض جميع الواجهات للتقديم والمناقشة',
            accent: const Color(0xFF4FC3F7),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ScreensGalleryScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.18), const Color(0xFF111827)],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: accent.withValues(alpha: 0.22),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onBack,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF111827)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        border: const Border(bottom: BorderSide(color: Color(0x221E88E5))),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'رجوع إلى المحادثات الخاصة',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
            )
          else
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.22),
              child: Icon(icon, color: const Color(0xFF1E88E5), size: 22),
            ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              Text(subtitle,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPublicScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildChatHeader(
          icon: Icons.forum_outlined,
          title: 'المحادثة العامة',
          subtitle: 'رسائل عامة تصل إلى الجميع',
        ),
        Expanded(child: _buildChatList(false)),
      ],
    );
  }

  Widget _buildPrivateScreen() {
    final inThread = _privateTarget != null && _inThread;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!inThread)
          _buildChatHeader(
            icon: Icons.lock_outline,
            title: 'المحادثات الخاصة',
            subtitle: 'محادثة مستقلة لكل عميل متصل — اضغط أي عميل للدخول',
          ),
        if (inThread)
          _buildChatHeader(
            icon: Icons.lock_outline,
            title: '$_privateTarget في محادثة خاصة',
            subtitle: 'المراسلة مع [$_privateTarget]',
            onBack: () => setState(() => _inThread = false),
          ),
        Expanded(
          child: inThread ? _buildChatList(true) : _buildConversationList(),
        ),
      ],
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.grey.shade600),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    if (_users.isEmpty) {
      return const Center(
        child: Text(
          'لا يوجد متصلون حالياً.\nستظهر محادثة خاصة تلقائياً عند اتصال أي عميل.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) => _buildConversationTile(_users[index]),
    );
  }

  Widget _buildConversationTile(String user) {
    final last = _latestPrivateFor(user);
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.18),
        child: Text(
          user.isNotEmpty ? user[0] : '?',
          style: const TextStyle(
              color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      title: Text(user, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        last.$1,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
      ),
      trailing: Text(
        last.$2,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
      ),
      onTap: () => setState(() {
        _privateTarget = user;
        _inThread = true;
      }),
    );
  }

  (String, String) _latestPrivateFor(String user) {
    String text = 'لا توجد رسائل بعد.';
    String time = '';
    for (final msg in _privateMessages.reversed) {
      if (msg.sender == user || msg.recipient == user) {
        text = msg.message;
        time = _formatTime(msg.timestamp);
        break;
      }
    }
    if (text == 'لا توجد رسائل بعد.') {
      for (final v in _privateVoices.reversed) {
        if (v.voice.sender == user || v.voice.recipient == user) {
          text = 'رسالة صوتية (${v.voice.durationSeconds} ثوانٍ)';
          time = _formatTime(v.voice.timestamp);
          break;
        }
      }
    }
    return (text, time);
  }

  Widget _buildUsersPanel() {
    return Container(
      color: const Color(0xFF111827),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const Icon(Icons.group, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text('المتصلون (${_users.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_users.contains(_privateTarget))
                  IconButton(
                    tooltip: 'إلغاء التحديد',
                    iconSize: 18,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _privateTarget = null),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _users.isEmpty
                ? _emptyState(
                    Icons.people_outline,
                    'لا يوجد متصلون',
                    'ستظهر القائمة هنا فور اتصال عملاء جدد',
                  )
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final selected = user == _privateTarget;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 15,
                          backgroundColor:
                              selected
                                  ? const Color(0xFF2ECC71).withValues(alpha: 0.22)
                                  : const Color(0xFF1E88E5).withValues(alpha: 0.18),
                          child: Text(
                            user.isNotEmpty ? user[0] : '?',
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFF2ECC71)
                                  : const Color(0xFF81C784),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(user),
                        selected: selected,
                        onTap: () => setState(() => _privateTarget = user),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              'حالة: ${_callActive ? 'في مكالمة' : 'متصل'}',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(bool private) {
    var messages = private ? _privateMessages : _publicMessages;
    var voices = private ? _privateVoices : _publicVoices;
    final scroll = private ? _privateScroll : _publicScroll;
    if (private && _privateTarget != null) {
      messages = messages
          .where((m) =>
              m.sender == _privateTarget || m.recipient == _privateTarget)
          .toList();
      voices = voices
          .where((v) =>
              v.voice.sender == _privateTarget ||
              v.voice.recipient == _privateTarget)
          .toList();
    }
    final fileList = _fileEntries.where(
        (e) => !private || e.sender != _localUsername);

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(8),
      children: [
        if (private && _privateTarget == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'اختر مستخدماً من قائمة المتصلين لبدء محادثة خاصة.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        if (private && _privateTarget != null && !_users.contains(_privateTarget))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'المستخدم [$_privateTarget] غير متصل حالياً.',
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        for (final msg in messages)
          _messageBubble(msg, private),
        for (final voice in voices)
          _voiceBubble(voice, private),
        for (final file in fileList)
          _fileBubble(file),
        if (messages.isEmpty && voices.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: _emptyState(
              Icons.forum_outlined,
              private ? 'لا توجد رسائل خاصة بعد' : 'لا توجد رسائل بعد',
              private
                  ? 'ابدأ محادثة خاصة أو أرسل رسالة صوتية أو ملفاً'
                  : 'أرسل أول رسالة عامة إلى المجموعة',
            ),
          ),
        if (fileList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Center(
              child: Text('لا توجد ملفات مستلمة أو مرسلة بعد',
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Widget _messageBubble(ChatMessageModel msg, bool private) {
    final isMe =
        msg.sender.toLowerCase() == _localUsername.toLowerCase();
    String header;
    if (isMe) {
      header = private ? 'أنت -> ${msg.recipient}' : 'أنت';
    } else {
      header = private ? '${msg.sender} -> أنت' : msg.sender;
    }

    return Align(
      alignment:
          isMe ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1E3A5F) : const Color(0xFF263043),
          borderRadius: isMe
              ? const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(5),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.isEncrypted)
              _encryptedBadge(header, isMe)
            else
              Text(header,
                  style: TextStyle(
                      color:
                          isMe ? const Color(0xFF4FC3F7) : const Color(0xFF81C784),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(msg.message,
                style: const TextStyle(fontSize: 14, color: Colors.white)),
            const SizedBox(height: 3),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                _formatTime(msg.timestamp),
                style: TextStyle(
                    color:
                        isMe ? const Color(0xFF90CAF9) : Colors.grey.shade500,
                    fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encryptedBadge(String header, bool isMe) {
    const amber = Color(0xFFFFB74D);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: amber.withValues(alpha: 0.5)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, size: 11, color: amber),
              SizedBox(width: 3),
              Text('مشفر',
                  style: TextStyle(
                      color: amber, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(header,
              style: TextStyle(
                  color:
                      isMe ? const Color(0xFF4FC3F7) : const Color(0xFF81C784),
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _voiceBubble(VoiceEntry entry, bool private) {
    final v = entry.voice;
    final isMe = v.sender.toLowerCase() == _localUsername.toLowerCase();
    String header;
    if (isMe) {
      header = private ? 'أنت -> ${v.recipient}' : 'أنت';
    } else {
      header = private ? '${v.sender} -> أنت' : v.sender;
    }

    return Align(
      alignment:
          isMe ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1E3A5F) : const Color(0xFF263043),
          borderRadius: isMe
              ? const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(5),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF2ECC71).withValues(alpha: 0.2),
              child: const Icon(Icons.graphic_eq,
                  color: Color(0xFF2ECC71), size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(header,
                    style: const TextStyle(
                        color: Color(0xFF81C784),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                Text('رسالة صوتية (${v.durationSeconds} ثوانٍ)',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.play_circle_fill,
                  color: Color(0xFF2ECC71), size: 32),
              onPressed: () => _playVoice(entry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileBubble(FileEntry entry) {
    final isMe = entry.sender == _localUsername;
    final header = isMe ? 'أنت أرسلت ملفاً' : 'ملف من [${entry.sender}]';
    return Align(
      alignment:
          isMe ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1E3A5F) : const Color(0xFF263043),
          borderRadius: isMe
              ? const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(5),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.insert_drive_file,
                  color: Color(0xFF1E88E5)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(header,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF90CAF9))),
                  const SizedBox(height: 3),
                  Text(entry.fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(
                    entry.done
                        ? '✓ تم الاستلام (${_formatBytes(entry.fileSize)})'
                        : 'جاري التحميل... قطعة (${entry.current}/${entry.total})',
                    style: TextStyle(
                        color: entry.done ? Colors.green : Colors.orange,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            if (entry.done)
              IconButton(
                icon: const Icon(Icons.folder_open, color: Colors.white),
                onPressed: _openDownloadsFolder,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xFF111827),
      child: Row(
        children: [
          IconButton(
            tooltip: 'تسجيل صوت',
            icon: Icon(
              _isRecordingVoice ? Icons.stop_circle : Icons.mic,
              color: _isRecordingVoice ? Colors.red : Colors.white,
            ),
            onPressed: _toggleVoiceNote,
          ),
          IconButton(
            tooltip: 'إرسال ملف',
            icon: const Icon(Icons.attach_file),
            onPressed: _pickAndSendFile,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: _mode == _ChatMode.private
                    ? (_privateTarget != null
                        ? 'رسالة خاصة إلى [$_privateTarget]...'
                        : 'اختر مستخدماً أولاً...')
                    : 'اكتب رسالة عامة...',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                filled: true,
              ),
              onSubmitted: (_) => _send(_mode == _ChatMode.private),
            ),
          ),
          IconButton(
            tooltip: 'تشفير',
            icon: Icon(
              _encrypted ? Icons.lock : Icons.lock_open,
              color: _encrypted ? Colors.green : Colors.white,
            ),
            onPressed: () => setState(() => _encrypted = !_encrypted),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: () => _send(_mode == _ChatMode.private),
            icon: const Icon(Icons.send),
            label: const Text('إرسال'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSetGlobalProfileCover() async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'صور',
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    final XFile? file =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) _showWarning('حجم الصورة كبير جداً (الحد 2MB).');
        return;
      }
      if (!mounted) return;
      setState(() {
        _globalProfileCoverBase64 = base64Encode(bytes);
      });
    } catch (_) {
      if (mounted) _showWarning('فشل قراءة الصورة.');
    }
  }

  Future<void> _pickAndSetGlobalProfileAvatar() async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'صور',
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    final XFile? file =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 1 * 1024 * 1024) {
        if (mounted) _showWarning('حجم الصورة كبير جداً (الحد 1MB).');
        return;
      }
      if (!mounted) return;
      setState(() {
        _globalProfileAvatarBase64 = base64Encode(bytes);
      });
    } catch (_) {
      if (mounted) _showWarning('فشل قراءة الصورة.');
    }
  }

  void _showWarning(String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تنبيه'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الملف الشخصي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_globalProfileAvatarBase64 != null)
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: MemoryImage(
                        base64Decode(_globalProfileAvatarBase64!)),
                  )
                else
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF1E88E5),
                    child: Icon(Icons.person,
                        color: Colors.white, size: 32),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('اسم المستخدم: $_localUsername',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('صورة وخلفية البروفايل تظهران لكل العملاء'),
            const SizedBox(height: 12),
            if (_globalProfileCoverBase64 != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(_globalProfileCoverBase64!),
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 90,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text('لا توجد خلفية بعد',
                    style: TextStyle(color: Colors.white70)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _pickAndSetGlobalProfileCover();
            },
            child: const Text('تغيير الخلفية'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _pickAndSetGlobalProfileAvatar();
            },
            child: const Text('تغيير الصورة'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF1E293B),
      child: Text(
        _status.isEmpty ? 'جاهز' : _status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
      ),
    );
  }

  String _formatTime(DateTime t) => formatArabicTime(t);
}

String formatArabicTime(DateTime t) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  String two(int n) {
    final s = n.toString().padLeft(2, '0');
    return s
        .split('')
        .map((c) => arabicDigits[c.codeUnitAt(0) - 0x30])
        .join();
  }

  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class VoiceEntry {
  VoiceEntry(this.voice);
  final VoiceMessageModel voice;
}

class FileEntry {
  FileEntry({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.sender,
  });

  final String transferId;
  final String fileName;
  final int fileSize;
  final String sender;
  int current = 0;
  int total = 1;
  bool done = false;
  String? savedPath;
}

class UserProfile {
  UserProfile({
    required this.username,
    this.avatarBase64,
    this.coverBase64,
  });

  final String username;
  String? avatarBase64;
  String? coverBase64;
}