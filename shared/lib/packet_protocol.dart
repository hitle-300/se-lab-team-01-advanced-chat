import 'dart:convert';
import 'dart:typed_data';

enum PacketType {
  connectRequest(1),
  connectResponse(2),
  userListUpdate(3),
  publicMessage(4),
  privateMessage(5),
  fileMetadata(6),
  fileChunk(7),
  fileComplete(8),
  disconnect(9),
  kickNotice(10),
  voiceMessage(11),
  videoFrame(12),
  callSignal(13);

  const PacketType(this.byte);
  final int byte;

  static PacketType fromByte(int value) {
    for (final type in PacketType.values) {
      if (type.byte == value) return type;
    }
    throw FormatException('Unknown packet type byte: $value');
  }
}

class NetworkPacket {
  NetworkPacket(this.type, [this.payload = const <int>[]]);

  final PacketType type;
  final List<int> payload;

  String get payloadAsUtf8 =>
      utf8.decode(payload, allowMalformed: true);
}

class PacketProtocol {
  static const int headerSize = 5;
  static const int maxChunkSize = 32 * 1024;
  static const int maxPayloadSize = 50 * 1024 * 1024;
}

List<int> framePacket(PacketType type, List<int> payload) {
  final header = ByteData(PacketProtocol.headerSize)
    ..setUint8(0, type.byte)
    ..setUint32(1, payload.length, Endian.big);
  return <int>[...header.buffer.asUint8List(), ...payload];
}

class PacketDecoder {
  final List<int> _buffer = <int>[];

  void write(List<int> chunk) => _buffer.addAll(chunk);

  NetworkPacket? tryDecode() {
    if (_buffer.length < PacketProtocol.headerSize) return null;
    final lengthBytes = Uint8List.fromList(_buffer.sublist(1, PacketProtocol.headerSize));
    final length = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
    if (length > PacketProtocol.maxPayloadSize) {
      _buffer.clear();
      throw FormatException('Invalid packet payload length: $length');
    }
    final total = PacketProtocol.headerSize + length;
    if (_buffer.length < total) return null;
    final type = PacketType.fromByte(_buffer[0]);
    final payload = _buffer.sublist(PacketProtocol.headerSize, total);
    _buffer.removeRange(0, total);
    return NetworkPacket(type, payload);
  }

  void clear() => _buffer.clear();
}