import 'dart:convert';
import 'dart:typed_data';

List<int> encode7BitInt(int value) {
  final result = <int>[];
  var l = value;
  while (l >= 0x80) {
    result.add((l & 0x7F) | 0x80);
    l >>= 7;
  }
  result.add(l);
  return result;
}

List<int> encodeInt32(int value) {
  final bd = ByteData(4)..setInt32(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

List<int> encodeInt64(int value) {
  final bd = ByteData(8)..setInt64(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

List<int> encodeDotNetString(String value) {
  final bytes = utf8.encode(value);
  return [...encode7BitInt(bytes.length), ...bytes];
}

class DotNetBinaryWriter {
  final List<int> _bytes = <int>[];

  void writeByte(int value) => _bytes.add(value & 0xFF);

  void writeInt32(int value) {
    _bytes.addAll(encodeInt32(value));
  }

  void writeInt64(int value) {
    _bytes.addAll(encodeInt64(value));
  }

  void writeString(String value) {
    _bytes.addAll(encodeDotNetString(value));
  }

  void writeBytes(List<int> value) {
    _bytes.addAll(value);
  }

  List<int> toBytes() => List<int>.unmodifiable(_bytes);
}

class DotNetBinaryReader {
  DotNetBinaryReader(List<int> bytes)
      : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        _pos = 0;

  final Uint8List _bytes;
  int _pos;

  int get remaining => _bytes.length - _pos;

  void _ensureAvailable(int count) {
    if (_pos + count > _bytes.length) {
      throw StateError('DotNetBinaryReader: end of stream');
    }
  }

  int readByte() {
    _ensureAvailable(1);
    return _bytes[_pos++] & 0xFF;
  }

  int readInt32() {
    _ensureAvailable(4);
    final value =
        ByteData.sublistView(_bytes, _pos, _pos + 4).getInt32(0, Endian.little);
    _pos += 4;
    return value;
  }

  int readInt64() {
    _ensureAvailable(8);
    final value =
        ByteData.sublistView(_bytes, _pos, _pos + 8).getInt64(0, Endian.little);
    _pos += 8;
    return value;
  }

  String readString() {
    var length = 0;
    var shift = 0;
    var read = 0;
    do {
      read = readByte();
      length |= (read & 0x7F) << shift;
      shift += 7;
      if (length > 0x7FFFFFFF) {
        throw StateError('DotNetBinaryReader: string length overflow');
      }
    } while ((read & 0x80) != 0);

    _ensureAvailable(length);
    final result =
        utf8.decode(_bytes.sublist(_pos, _pos + length));
    _pos += length;
    return result;
  }

  List<int> readBytes(int count) {
    _ensureAvailable(count);
    final result = _bytes.sublist(_pos, _pos + count);
    _pos += count;
    return result;
  }
}