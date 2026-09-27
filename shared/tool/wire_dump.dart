import 'dart:typed_data';

import 'package:shared/shared.dart';

/// أداة سطر أوامر لتفريغ بايتات البروتوكول بصيغة قابلة للمقارنة
/// مع التقاط .NET (WireShark / سجل BinaryWriter).
String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void printHeader(PacketType type, int payloadLength) {
  final header = ByteData(PacketProtocol.headerSize)
    ..setUint8(0, type.byte)
    ..setUint32(1, payloadLength, Endian.big);
  print('Header [${type.name}] (payload=$payloadLength bytes):');
  print('  ${hexOf(header.buffer.asUint8List())}');
}

void dumpModel(PacketType type, List<int> payload) {
  print('${type.name}:');
  print('  payload (${payload.length} b): ${hexOf(payload)}');
  printHeader(type, payload.length);
  final framed = framePacket(type, payload);
  print('  framed  (${framed.length} b): ${hexOf(framed)}');
  print('');
}

void main() {
  print('=== wire_dump: تفريغ بايتات البروتوكول (مقارنة مع نظير .NET) ===');
  print('');

  final message = ChatMessageModel(
    sender: 'أحمد',
    recipient: 'سارة',
    message: 'مرحباً بالعالم',
    timestamp: DateTime.fromMicrosecondsSinceEpoch(0),
    isEncrypted: false,
  );
  dumpModel(PacketType.privateMessage, message.serialize());

  final file = FileHeaderModel(
    transferId: 'fid-001',
    fileName: 'تقرير.pdf',
    fileSize: 1048576,
    sender: 'أحمد',
    recipient: '',
  );
  dumpModel(PacketType.fileMetadata, file.serialize());

  final voice = VoiceMessageModel(
    sender: 'أحمد',
    recipient: 'سارة',
    durationSeconds: 4,
    audioData: [0xDE, 0xAD, 0xBE, 0xEF],
    timestamp: DateTime.fromMicrosecondsSinceEpoch(0),
  );
  dumpModel(PacketType.voiceMessage, voice.serialize());
}