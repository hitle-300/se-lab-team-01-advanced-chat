import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'database_manager.dart';

const List<String> messageFilterTypes = ['الكل', 'عامة', 'خاصة', 'إشعار إداري'];

const Map<String, List<String>> _tableColumns = {
  'Clients': [
    'ClientId',
    'Username',
    'IpAddress',
    'Port',
    'FirstSeen',
    'LastSeen',
    'TotalConnections',
    'TotalMessagesSent',
    'Status',
    'IsBanned',
    'BanReason',
    'BannedUntil',
  ],
  'ChatMessages': [
    'MessageId',
    'Sender',
    'Recipient',
    'MessageType',
    'MessageContent',
    'IsEncrypted',
    'Timestamp',
    'SenderIp',
  ],
  'ClientSessions': [
    'SessionId',
    'Username',
    'IpAddress',
    'Port',
    'ConnectedAt',
    'DisconnectedAt',
    'DurationSeconds',
    'SessionState',
  ],
  'FileTransfers': [
    'TransferId',
    'Sender',
    'Recipient',
    'FileName',
    'FileSize',
    'Timestamp',
    'Status',
  ],
};

const Map<String, Map<String, String>> _arabicHeaders = {
  'Clients': {
    'ClientId': 'المعرف',
    'Username': 'اسم العميل',
    'IpAddress': 'عنوان الـ IP',
    'Port': 'المنفذ',
    'FirstSeen': 'أول تسجيل',
    'LastSeen': 'آخر ظهور',
    'TotalConnections': 'عدد الاتصالات',
    'TotalMessagesSent': 'إجمالي الرسائل',
    'Status': 'الحالة',
    'IsBanned': 'محظور',
    'BanReason': 'سبب الحظر',
    'BannedUntil': 'انتهاء الحظر',
  },
  'ChatMessages': {
    'MessageId': '#',
    'Sender': 'المرسل',
    'Recipient': 'المستلم',
    'MessageType': 'نوع الرسالة',
    'MessageContent': 'محتوى الرسالة',
    'IsEncrypted': 'مشفرة (AES)',
    'Timestamp': 'التوقيت',
    'SenderIp': 'IP المرسل',
  },
  'ClientSessions': {
    'SessionId': '#',
    'Username': 'العميل',
    'IpAddress': 'عنوان IP',
    'Port': 'المنفذ',
    'ConnectedAt': 'وقت الاتصال',
    'DisconnectedAt': 'وقت الانفصال',
    'DurationSeconds': 'المدة (ثواني)',
    'SessionState': 'حالة الجلسة',
  },
  'FileTransfers': {
    'TransferId': 'معرف النقل',
    'Sender': 'المرسل',
    'Recipient': 'المستلم',
    'FileName': 'اسم الملف',
    'FileSize': 'الحجم (بايت)',
    'Timestamp': 'التوقيت',
    'Status': 'الحالة',
  },
};

String _cell(Object? value) {
  if (value == null) return '';
  if (value is bool) return value ? 'True' : 'False';
  if (value is num) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  return value.toString();
}

class DatabaseViewerPage extends StatefulWidget {
  const DatabaseViewerPage({super.key, required this.db});

  final DatabaseManager db;

  @override
  State<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends State<DatabaseViewerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'الكل';
  String _messageSort = 'الأحدث أولاً';
  int _page = 0;
  static const int _messagesPerPage = 25;
  int _tabIndex = 0;

  final Map<String, List<Map<String, Object?>>> _rows = {
    'Clients': [],
    'ChatMessages': [],
    'ClientSessions': [],
    'FileTransfers': [],
  };

  String _stats = '';

  static const List<String> _tabs = [
    'Clients',
    'ChatMessages',
    'ClientSessions',
    'FileTransfers',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final clients = await widget.db.queryClients();
      final messages = await widget.db.queryChatMessages();
      final sessions = await widget.db.querySessions();
      final files = await widget.db.queryFileTransfers();
      if (!mounted) return;
      setState(() {
        _rows['Clients'] = clients;
        _rows['ChatMessages'] = messages;
        _rows['ClientSessions'] = sessions;
        _rows['FileTransfers'] = files;
      });
      _updateStats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء تحميل بيانات الجداول: $e')),
      );
    }
  }

  Future<void> _updateStats() async {
    try {
      final stats = await widget.db.getDatabaseStats();
      if (!mounted) return;
      final sizeKb = (stats['dbSize'] ?? 0) / 1024.0;
      String sizeText;
      if (sizeKb == sizeKb.roundToDouble()) {
        sizeText = sizeKb.round().toString();
      } else {
        sizeText = sizeKb.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
      }
      setState(() {
        _stats = '📊 إجمالي العملاء: ${stats['clients']} | '
            'إجمالي الرسائل المخزنة: ${stats['messages']} | '
            'سجلات الجلسات: ${stats['sessions']} | '
            'حجم الملف: $sizeText KB';
      });
    } catch (_) {}
  }

  void _applyFilter() {
    setState(() {
      _page = 0;
    });
  }

  int _messageIdOf(Map<String, Object?> row) {
    final value = row['MessageId'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, Object?>> _filteredRows() {
    final table = _tabs[_tabIndex];
    final source = _rows[table] ?? [];
    final keyword = _searchController.text.trim().toLowerCase();
    final List<Map<String, Object?>> result;
    if (keyword.isEmpty && (table != 'ChatMessages' || _filterType == 'الكل')) {
      result = source.toList();
    } else {
      result = source.where((row) {
        String check(String key) =>
            (row[key]?.toString() ?? '').toLowerCase();
        switch (table) {
          case 'Clients':
            if (keyword.isEmpty) return true;
            return check('Username').contains(keyword) ||
                check('IpAddress').contains(keyword);
          case 'ChatMessages':
            var ok = true;
            if (keyword.isNotEmpty) {
              ok = check('Sender').contains(keyword) ||
                  check('Recipient').contains(keyword) ||
                  check('MessageContent').contains(keyword);
            }
            if (_filterType != 'الكل') {
              ok = ok && check('MessageType') == _filterType;
            }
            return ok;
          case 'ClientSessions':
            if (keyword.isEmpty) return true;
            return check('Username').contains(keyword) ||
                check('IpAddress').contains(keyword);
          case 'FileTransfers':
            if (keyword.isEmpty) return true;
            return check('Sender').contains(keyword) ||
                check('Recipient').contains(keyword) ||
                check('FileName').contains(keyword);
        }
        return true;
      }).toList();
    }

    if (table == 'ChatMessages') {
      final newest = _messageSort == 'الأحدث أولاً';
      result.sort((a, b) {
        final cmp = _messageIdOf(a).compareTo(_messageIdOf(b));
        return newest ? -cmp : cmp;
      });
    }
    return result;
  }

  int get _totalFiltered => _filteredRows().length;

  int get _totalPages {
    final total = _totalFiltered;
    if (total == 0) return 1;
    return (total / _messagesPerPage).ceil();
  }

  List<Map<String, Object?>> _visibleRows() {
    final all = _filteredRows();
    if (_tabs[_tabIndex] != 'ChatMessages') return all;
    if (_page >= _totalPages) _page = _totalPages - 1;
    if (_page < 0) _page = 0;
    final start = _page * _messagesPerPage;
    if (start >= all.length) return const [];
    final end = (start + _messagesPerPage) < all.length
        ? start + _messagesPerPage
        : all.length;
    return all.sublist(start, end);
  }

  Future<void> _exportSql() async {
    try {
      final now = DateTime.now();
      final stamp = '${now.year}${_two(now.month)}${_two(now.day)}_'
          '${_two(now.hour)}${_two(now.minute)}';
      const group = XTypeGroup(label: 'ملف سكربت SQL (*.sql)', extensions: ['sql']);
      final location = await getSaveLocation(
        suggestedName: 'ChatServer_DB_Dump_$stamp.sql',
        acceptedTypeGroups: const [group],
      );
      final path = location?.path;
      if (path == null || path.isEmpty) return;
      await widget.db.exportFullDatabaseToSql(path);
      _showInfo('تم تصدير كامل قاعدة البيانات بنجاح إلى:\n$path\n\n'
          'يمكنك فتح هذا الملف في أي محرر أو استيراده في MySQL أو SQLite أو SQL Server.');
    } catch (e) {
      _showError('خطأ أثناء تصدير SQL: $e');
    }
  }

  Future<void> _exportCsv() async {
    try {
      final table = _tabs[_tabIndex];
      final now = DateTime.now();
      final stamp = '${now.year}${_two(now.month)}${_two(now.day)}_'
          '${_two(now.hour)}${_two(now.minute)}';
      final defaultName = switch (table) {
        'ChatMessages' => 'ChatMessages',
        'ClientSessions' => 'ClientSessions',
        'FileTransfers' => 'FileTransfers',
        _ => 'Clients',
      };
      const group = XTypeGroup(label: 'ملف CSV (*.csv)', extensions: ['csv']);
      final location = await getSaveLocation(
        suggestedName: '${defaultName}_$stamp.csv',
        acceptedTypeGroups: const [group],
      );
      final path = location?.path;
      if (path == null || path.isEmpty) return;
      final columns = _tableColumns[table]!;
      await widget.db.exportTableToCsv(_rows[table]!, columns, path);
      _showInfo('تم تصدير الجدول بنجاح إلى:\n$path\n\nيمكن فتحه مباشرة باستخدام Microsoft Excel.');
    } catch (e) {
      _showError('خطأ أثناء تصدير CSV: $e');
    }
  }

  Future<void> _exportAllTablesCsv() async {
    try {
      final directory = await getDirectoryPath();
      if (directory == null || directory.isEmpty) return;
      final now = DateTime.now();
      final stamp = '${now.year}${_two(now.month)}${_two(now.day)}_'
          '${_two(now.hour)}${_two(now.minute)}';
      final written = <String>[];
      final counts = <String, int>{};
      for (final table in _tabs) {
        final columns = _tableColumns[table]!;
        final fileName = '${table}_$stamp.csv';
        final rows = _rows[table]!;
        await widget.db.exportTableToCsv(
          rows,
          columns,
          '$directory/$fileName',
        );
        written.add(fileName);
        counts[table] = rows.length;
      }
      _showInfo('تم تصدير جميع الجداول (${written.length}) بنجاح:\n'
          '${counts.entries.map((e) => '${e.key}: ${e.value} صف').join('\n')}\n\n'
          'إلى المجلد:\n$directory');
    } catch (e) {
      _showError('خطأ أثناء تصدير CSV: $e');
    }
  }

  Future<void> _clearDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد مسح قاعدة البيانات'),
        content: const Text(
            'تحذير: هل أنت متأكد من رغبتك في مسح كافة سجلات قاعدة البيانات؟\n'
            '(سيتم حذف جميع رسائل الدردشة، والعملاء، والجلسات نهائياً)'),
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
    if (confirmed == true) {
      await widget.db.clearDatabase();
      await _load();
      _showInfo('تم تفريغ قاعدة البيانات بنجاح.');
    }
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تمت العملية'),
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

  void _showError(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('خطأ'),
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

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final table = _tabs[_tabIndex];
    final columns = _tableColumns[table]!;
    final headers = _arabicHeaders[table]!;
    final totalPages = _totalPages;
    final rows = _visibleRows();
    final isMessages = table == 'ChatMessages';

    return Scaffold(
      appBar: AppBar(
        title: const Text('عارض قاعدة البيانات وكل السجلات'),
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'تصدير SQL',
            icon: const Icon(Icons.save_alt),
            onPressed: _exportSql,
          ),
          IconButton(
            tooltip: 'تصدير CSV',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: _exportCsv,
          ),
          IconButton(
            tooltip: 'تصدير كل الجداول CSV',
            icon: const Icon(Icons.folder_zip_outlined),
            onPressed: _exportAllTablesCsv,
          ),
          IconButton(
            tooltip: 'مسح قاعدة البيانات',
            icon: const Icon(Icons.delete_forever),
            onPressed: _clearDatabase,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => _applyFilter(),
                        decoration: const InputDecoration(
                          labelText: 'بحث...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _filterType,
                      items: [
                        for (final t in messageFilterTypes)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _filterType = value;
                            _page = 0;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(_stats, style: const TextStyle(color: Color(0xFF2C3E50))),
                ),
              ],
            ),
          ),
          TabBar(
            tabs: const [
              Tab(text: 'العملاء'),
              Tab(text: 'الرسائل'),
              Tab(text: 'الجلسات'),
              Tab(text: 'نقل الملفات'),
            ],
            onTap: (index) => setState(() {
              _tabIndex = index;
              _page = 0;
            }),
          ),
          const Divider(height: 1),
          if (isMessages)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  const Text('الترتيب:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _messageSort,
                    items: const [
                      DropdownMenuItem(
                          value: 'الأحدث أولاً', child: Text('الأحدث أولاً')),
                      DropdownMenuItem(
                          value: 'الأقدم أولاً', child: Text('الأقدم أولاً')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _messageSort = value;
                          _page = 0;
                        });
                      }
                    },
                  ),
                  const Spacer(),
                  Text('الصفحة ${_page + 1} من $totalPages | '
                      'إجمالي $_totalFiltered رسالة'),
                  IconButton(
                    tooltip: 'السابق',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _page > 0
                        ? () => setState(() => _page = _page - 1)
                        : null,
                  ),
                  IconButton(
                    tooltip: 'التالي',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _page + 1 < totalPages
                        ? () => setState(() => _page = _page + 1)
                        : null,
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('لا توجد بيانات'))
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                            const Color(0xFF2C3E50)),
                        headingTextStyle:
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        columns: [
                          for (final col in columns)
                            DataColumn(label: Text(headers[col] ?? col)),
                        ],
                        rows: [
                          for (final row in rows)
                            DataRow(cells: [
                              for (final col in columns)
                                DataCell(Text(
                                  _cell(row[col]),
                                  overflow: TextOverflow.ellipsis,
                                )),
                            ]),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}