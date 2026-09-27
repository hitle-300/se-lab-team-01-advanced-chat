import 'dart:io';
import 'dart:math';

class ClientSession {
  ClientSession(this.socket)
      : id = _randomId(),
        connectedAt = DateTime.now();

  final String id;
  final Socket socket;
  final DateTime connectedAt;

  String? username;
  int bytesReceived = 0;
  int bytesSent = 0;

  Future<void> _writeTail = Future.value();

  String get remoteEndpoint {
    try {
      return '${socket.remoteAddress.address}:${socket.remotePort}';
    } catch (_) {
      return 'unknown';
    }
  }

  InternetAddress get remoteAddress {
    try {
      return socket.remoteAddress;
    } catch (_) {
      return InternetAddress.anyIPv4;
    }
  }

  int get remotePort {
    try {
      return socket.remotePort;
    } catch (_) {
      return 0;
    }
  }

  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      socket.close();
    } catch (_) {
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  /// يُرتب إرسال الدفعات عبر نفس المقبس بالترتيب (بمثابة WriteLock).
  Future<void> queueSend(List<int> bytes) {
    final result = _writeTail.then((_) {
      try {
        if (_closed) return;
        socket.add(bytes);
      } catch (_) {}
    }).catchError((_) {});
    _writeTail = result;
    return result;
  }

  @override
  String toString() =>
      (username == null || username!.isEmpty) ? remoteEndpoint : '$username ($remoteEndpoint)';

  static String _randomId() {
    final rand = Random();
    var sb = StringBuffer();
    for (var i = 0; i < 8; i++) {
      sb.write(rand.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }
}