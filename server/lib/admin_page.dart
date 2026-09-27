import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'async_server.dart';
import 'client_session.dart';
import 'database_manager.dart';
import 'database_viewer_page.dart';
import 'kick_dialog.dart';
import 'server_config.dart';

Color logColorFor(String type) {
  switch (type) {
    case 'AUTH':
    case 'INFO':
      return const Color(0xFF006400);
    case 'SOCKET':
      return const Color(0xFF483D8B);
    case 'CHAT_PUB':
      return const Color(0xFF000080);
    case 'CHAT_PRIV':
      return const Color(0xFF800080);
    case 'FILE_META':
    case 'FILE_DONE':
      return const Color(0xFFFF8C00);
    case 'WARN':
    case 'DISCONNECT':
      return const Color(0xFFB8860B);
    case 'VOICE':
      return const Color(0xFF008080);
    case 'VIDEO':
    case 'CALL':
      return const Color(0xFF8B008B);
    case 'ERROR':
    case 'KICK':
    case 'BAN':
      return const Color(0xFFDC143C);
    default:
      return const Color(0xFF111111);
  }
}

class _LogEntry {
  _LogEntry(this.time, this.type, this.source, this.message)
      : color = logColorFor(type);

  final String time;
  final String type;
  final String source;
  final String message;
  final Color color;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTimeHms(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.db});

  final DatabaseManager db;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final AsyncServer _server;
  final TextEditingController _portController =
      TextEditingController(text: '8989');
  final ScrollController _logScrollController = ScrollController();

  final List<String> _ipChoices = [];
  int _ipIndex = 0;
  bool _running = false;

  final List<ClientSession> _clients = [];
  int? _selectedClient;

  final List<_LogEntry> _logEntries = [];
  bool _autoScroll = true;
  int _totalBytes = 0;
  int _totalPackets = 0;

  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _server = AsyncServer(database: widget.db);
    _wireEvents();
    _loadSavedConfig();
    _initIpChoices();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await _server.stop();
        await widget.db.close();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _portController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _wireEvents() {
    _server.approveConnection = _onApprovalRequested;
    _server.onLog = (type, source, message) {
      if (!mounted) return;
      setState(() {
        _logEntries.add(_LogEntry(_formatTimeHms(DateTime.now()), type, source,
            message));
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScrollController.hasClients) {
            _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
          }
        });
      }
    };
    _server.onClientJoined = (session) {
      if (!mounted) return;
      setState(() => _clients.add(session));
    };
    _server.onClientLeft = (session) {
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _clients.length; i++) {
          if (_clients[i].username == session.username) {
            _clients.removeAt(i);
            break;
          }
        }
        if (_selectedClient != null && _selectedClient! >= _clients.length) {
          _selectedClient = null;
        }
      });
    };
    _server.onStatsUpdated = (bytes, packets) {
      if (!mounted) return;
      setState(() {
        _totalBytes = bytes;
        _totalPackets = packets;
      });
    };
    _server.onStateChanged = (running) {
      if (!mounted) return;
      setState(() {
        _running = running;
        if (!running) _clients.clear();
        _selectedClient = null;
      });
    };
  }

  ServerConfig? _savedConfig;

  Future<void> _loadSavedConfig() async {
    final config = await ServerConfig.load();
    if (!mounted) return;
    setState(() => _savedConfig = config);
  }

  void _applySavedConfigToUi() {
    final config = _savedConfig;
    if (config == null || _ipChoices.isEmpty) return;
    _portController.text = config.port.toString();
    final ip = config.ip;
    int idx;
    if (ip == '127.0.0.1') {
      idx = 2;
    } else if (ip == '0.0.0.0') {
      idx = 0;
    } else {
      final lanIdx = _ipChoices.indexWhere((c) {
        final first = c.split(' ').first.trim();
        return first == ip;
      });
      idx = lanIdx >= 0 ? lanIdx : 1;
    }
    if (idx < _ipChoices.length) {
      _ipIndex = idx;
    }
  }

  Future<void> _initIpChoices() async {
    String bestLan = '192.168.128.243';
    try {
      bestLan = await AsyncServer.bestLanIpString();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _ipChoices
        ..add('0.0.0.0 (أي واجهة شبكة - يستقبل من الكل)')
        ..add('$bestLan (شبكة Wi-Fi الحالية)')
        ..add('127.0.0.1 (الجهاز المحلي فقط)');
      _applySavedConfigToUi();
    });
    if (!_running) {
      await _startServer();
    }
  }

  Future<bool> _onApprovalRequested(String username, ClientSession session) async {
    // اتصالات الآلة المحلية (تشمل USB reverse من الجوال) تُقبل تلقائياً؛
    // أما الاتصالات من أجهزة الشبكة فتبقى بموافقة يدوية كما هي شاشة C#.
    if (session.remoteAddress.isLoopback) {
      return true;
    }
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('طلب موافقة على اتصال جديد'),
        content: Text(
            'طلب اتصال وارد إلى الخادم:\n\n'
            'العميل: [$username]\n'
            'العنوان: ${session.remoteEndpoint}\n\n'
            'هل توافق على قبول اتصاله بالشبكة؟'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('نعم'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لا'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  Future<void> _startServer() async {
    final portText = _portController.text.trim();
    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      _showMessage('يرجى إدخال رقم منفذ صالح بين 1 و 65535',
          title: 'خطأ في الإدخال');
      return;
    }

    final selectedStr = _ipIndex >= 0 && _ipIndex < _ipChoices.length
        ? _ipChoices[_ipIndex]
        : '';
    InternetAddress selectedIp;
    if (selectedStr.contains('127.0.0.1')) {
      selectedIp = InternetAddress.loopbackIPv4;
    } else if (selectedStr.contains('0.0.0.0')) {
      selectedIp = InternetAddress.anyIPv4;
    } else {
      final ipPart = selectedStr.split(' ').first.trim();
      selectedIp = InternetAddress.tryParse(ipPart) ?? InternetAddress.anyIPv4;
    }

    final saved = await ServerConfig.save(
      ip: selectedIp.address,
      port: port,
    );
    if (saved && mounted) {
      setState(() {
        _savedConfig = ServerConfig(ip: selectedIp.address, port: port);
      });
    }

    try {
      await _server.start(selectedIp, port);
    } catch (e) {
      _showMessage('تعذر تشغيل الخادم: $e', title: 'خطأ في السوكيت');
    }
  }

  Future<void> _stopServer() async {
    await _server.stop();
  }

  Future<void> _kickSelected() async {
    final index = _selectedClient;
    if (index == null || index >= _clients.length) {
      _showMessage('يرجى تحديد عميل من القائمة أولاً لطرده.', title: 'تنبيه');
      return;
    }
    final username = _clients[index].username;
    if (username == null || username.isEmpty) return;
    final reason = await showKickDialog(context, username);
    if (reason != null && reason.isNotEmpty) {
      await _server.kickClient(username, reason, banMinutes: 5);
    }
  }

  Future<void> _broadcast() async {
    final notice = await showPromptDialog(
      context,
      title: 'إرسال إشعار عام (Broadcast)',
      prompt: 'أدخل نص الإشعار أو التنبيه الإداري لبثه لجميع العملاء المتصلين:',
      defaultValue: 'تنبيه من إدارة الخادم: مرحباً بالجميع',
    );
    if (notice == null || notice.trim().isEmpty) return;

    try {
      await widget.db.saveChatMessage(
        '[تنبيه الإدارة]',
        'الجميع (عامة)',
        notice.trim(),
        false,
        'إشعار إداري',
        '127.0.0.1',
      );
    } catch (_) {}

    final msg = ChatMessageModel(
      sender: '[تنبيه الإدارة]',
      recipient: '',
      message: notice.trim(),
      timestamp: DateTime.now(),
    );
    await _server.broadcastPacket(PacketType.publicMessage, msg.serialize());
    _logEntries.add(_LogEntry(_formatTimeHms(DateTime.now()), 'INFO',
        'ADMIN', 'تم بث إشعار إداري إلى جميع العملاء.'));
  }

  void _openDatabaseViewer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DatabaseViewerPage(db: widget.db),
      ),
    );
  }

  void _clearLog() {
    setState(() => _logEntries.clear());
  }

  void _showMessage(String message, {required String title}) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = _running ? const Color(0xFF2ECC71) : const Color(0xFFC0392B);
    final badgeText = _running ? 'الخادم نشط' : 'الخادم متوقف';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.dns, color: Color(0xFF2C3E50), size: 26),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'إدارة الخادم - نظام تبادل البيانات (Server)',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          const Text('عنوان الاستماع:'),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 320,
                            child: DropdownButton<String>(
                              value: _ipIndex < _ipChoices.length
                                  ? _ipChoices[_ipIndex]
                                  : null,
                              isExpanded: true,
                              hint: const Text('جارٍ تحميل العناوين...'),
                              items: [
                                for (final ip in _ipChoices)
                                  DropdownMenuItem(value: ip, child: Text(ip)),
                              ],
                              onChanged: _running
                                  ? null
                                  : (value) {
                                      final idx = _ipChoices.indexOf(value!);
                                      if (idx >= 0) {
                                        setState(() => _ipIndex = idx);
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text('المنفذ:'),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: _portController,
                              enabled: !_running,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: _running ? null : _startServer,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('تشغيل الخادم'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFC0392B),
                            ),
                            onPressed: _running ? _stopServer : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('إيقاف الخادم'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _running
                            ? 'الحالة: نشط على المنفذ ${_server.port} | للاتصال من أجهزة أخرى بالشبكة اكتب في العميل IP: ${_ipChoices.isNotEmpty ? _ipChoices[1].split(' ').first : ''}'
                            : 'الحالة: الخادم غير مشغل',
                        style: const TextStyle(
                            color: Color(0xFF2C3E50),
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'العملاء المتصلين: ${_clients.length} | '
                        'إجمالي الحزم: $_totalPackets | '
                        'حجم البيانات: ${AsyncServer.formatBytes(_totalBytes)}',
                        style: const TextStyle(color: Color(0xFF34495E)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 330,
                      child: Card(
                        elevation: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                'العملاء المتصلون (${_clients.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF2C3E50)),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _clients.isEmpty
                                  ? const Center(
                                      child: Text('لا يوجد عملاء متصلون',
                                          style: TextStyle(
                                              color: Color(0xFF7F8C8D))))
                                  : ListView.builder(
                                      itemCount: _clients.length,
                                      itemBuilder: (context, index) {
                                        final session = _clients[index];
                                        final selected =
                                            _selectedClient == index;
                                        return InkWell(
                                          onTap: () => setState(() =>
                                              _selectedClient = index),
                                          child: Container(
                                            color: selected
                                                ? const Color(0xFFD6EAF8)
                                                : null,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.person,
                                                    size: 18,
                                                    color: Color(0xFF2C3E50)),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        session.username ?? '',
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold),
                                                      ),
                                                      Text(
                                                        session.remoteEndpoint,
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: Color(
                                                                0xFF7F8C8D)),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  _formatTimeHms(
                                                      session.connectedAt),
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF7F8C8D)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFC0392B),
                                ),
                                onPressed: _kickSelected,
                                icon: const Icon(Icons.block),
                                label: const Text('طرد عميل (Kick)'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Card(
                        elevation: 2,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  const Text(
                                    'سجل الأحداث',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF2C3E50)),
                                  ),
                                  const Spacer(),
                                  const Text('التمرير التلقائي'),
                                  Checkbox(
                                    value: _autoScroll,
                                    onChanged: (value) => setState(
                                        () => _autoScroll = value ?? true),
                                  ),
                                  IconButton(
                                    tooltip: 'مسح السجل',
                                    icon: const Icon(Icons.delete_sweep),
                                    onPressed: _clearLog,
                                  ),
                                  IconButton(
                                    tooltip: 'بث إشعار للمتصلين',
                                    icon: const Icon(Icons.campaign),
                                    onPressed: _broadcast,
                                  ),
                                  IconButton(
                                    tooltip: 'عرض قاعدة البيانات وكل السجلات',
                                    icon: const Icon(Icons.storage),
                                    onPressed: _openDatabaseViewer,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _logEntries.isEmpty
                                  ? const Center(
                                      child: Text('لا توجد أحداث مسجلة بعد',
                                          style: TextStyle(
                                              color: Color(0xFF7F8C8D))))
                                  : ListView.builder(
                                      controller: _logScrollController,
                                      itemCount: _logEntries.length,
                                      itemBuilder: (context, index) {
                                        final entry = _logEntries[index];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.time,
                                                style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 12,
                                                    color: Color(0xFF95A5A6)),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 6,
                                                    vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: entry.color
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  entry.type,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: entry.color),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '${entry.source}: ${entry.message}',
                                                  style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: entry.color),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}