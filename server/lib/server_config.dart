import 'dart:convert';
import 'dart:io';

/// نموذج إعدادات الخادم المحفوظة في server/server_config.json
/// بحيث يحتفظ البرنامج بالمنفذ وعنوان الاستماع بين جلسات التشغيل.
class ServerConfig {
  const ServerConfig({this.ip = defaultIp, this.port = defaultPort});

  final String ip;
  final int port;

  static const String defaultIp = '0.0.0.0';
  static const int defaultPort = 8989;

  static File configFile() => File('server/server_config.json');

  static Future<ServerConfig> load() async {
    try {
      final file = configFile();
      if (!await file.exists()) return const ServerConfig();
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ip = (data['ip'] as String?)?.trim();
      final port = (data['port'] as num?)?.toInt();
      return ServerConfig(
        ip: (ip == null || ip.isEmpty) ? defaultIp : ip,
        port: (port == null || port < 1 || port > 65535) ? defaultPort : port,
      );
    } catch (_) {
      return const ServerConfig();
    }
  }

  static Future<bool> save({required String ip, required int port}) async {
    try {
      final file = configFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'ip': ip, 'port': port}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}