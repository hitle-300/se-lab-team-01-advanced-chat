import 'dart:convert';
import 'dart:typed_data';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('PacketProtocol', () {
    test('القيم الثنائية لأنواع الحزم مطابقة لـ PacketType.cs', () {
      expect(PacketType.connectRequest.byte, 1);
      expect(PacketType.connectResponse.byte, 2);
      expect(PacketType.userListUpdate.byte, 3);
      expect(PacketType.publicMessage.byte, 4);
      expect(PacketType.privateMessage.byte, 5);
      expect(PacketType.fileMetadata.byte, 6);
      expect(PacketType.fileChunk.byte, 7);
      expect(PacketType.fileComplete.byte, 8);
      expect(PacketType.disconnect.byte, 9);
      expect(PacketType.kickNotice.byte, 10);
      expect(PacketType.voiceMessage.byte, 11);
      expect(PacketType.videoFrame.byte, 12);
      expect(PacketType.callSignal.byte, 13);
      expect(PacketProtocol.headerSize, 5);
      expect(PacketProtocol.maxChunkSize, 32 * 1024);
      expect(PacketProtocol.maxPayloadSize, 50 * 1024 * 1024);
    });
  });

  group('DotNetBinary (توافق حرفي مع BinaryWriter)', () {
    test('ترميز 7-bit للطول مطابق للمواصفة', () {
      expect(encode7BitInt(5), [0x05]);
      expect(encode7BitInt(127), [0x7F]);
      expect(encode7BitInt(128), [0x80, 0x01]);
      expect(encode7BitInt(300), [0xAC, 0x02]);
    });

    test('int32 يُكتب Big/Little-endian كما في .NET (Little-Endian)', () {
      expect(encodeInt32(5), [0x05, 0x00, 0x00, 0x00]);
      expect(encodeInt32(-1), [0xFF, 0xFF, 0xFF, 0xFF]);
    });

    test('كتابة سلسلة "Hello" تطابق بايتات BinaryWriter حرفياً', () {
      final w = DotNetBinaryWriter()
        ..writeInt32(5)
        ..writeString('Hello');
      expect(
        w.toBytes(),
        [0x05, 0x00, 0x00, 0x00, 0x05, 0x48, 0x65, 0x6C, 0x6C, 0x6F],
      );
    });

    test('قراءة وكتابة Round-Trip لسلسلة عربية متعددة البايت', () {
      const text = 'مرحباً بك في الخادم الشبكي';
      final w = DotNetBinaryWriter()..writeString(text);
      final r = DotNetBinaryReader(w.toBytes());
      expect(r.readString(), text);
      expect(r.remaining, 0);
    });

    test('قراءة حزمة مركبة تتضمن Long وBytes', () {
      final w = DotNetBinaryWriter()
        ..writeInt64(637918080000000000)
        ..writeInt32(7)
        ..writeBytes([0xDE, 0xAD, 0xBE, 0xEF]);
      final r = DotNetBinaryReader(w.toBytes());
      expect(r.readInt64(), 637918080000000000);
      expect(r.readInt32(), 7);
      expect(r.readBytes(4), [0xDE, 0xAD, 0xBE, 0xEF]);
      expect(r.remaining, 0);
    });

    test('استثناء عند نهاية البيانات', () {
      final r = DotNetBinaryReader([0x01, 0x02]);
      expect(() => r.readInt32(), throwsStateError);
    });

    test('سلاسل عربية بفراغات ومسافات وtab ضمن البايتات الأصلية', () {
      final writer = DotNetBinaryWriter()
        ..writeString('   مرحباً بالعالم  ')
        ..writeString('a b\tc\n')
        ..writeString('ض');
      final bytes = writer.toBytes();
      // الفضاءات عربياً تُشفر فعلاً كبايتات UTF-8 وليست حشوة
      expect(
        bytes.sublist(0, bytes.length - utf8.encode('ض').length - 1),
        containsAllInOrder(utf8.encode('مرحباً')),
      );
      final reader = DotNetBinaryReader(bytes);
      expect(reader.readString(), '   مرحباً بالعالم  ');
      expect(reader.readString(), 'a b\tc\n');
      expect(reader.readString(), 'ض');
      expect(reader.remaining, 0);
    });

    test('نصوص متعددة البايت تشمل emoji وترميز 7-bit متعدد البايتات للطول', () {
      final text = 'نص طويل جداً ' * 15;
      expect(utf8.encode(text).length, greaterThan(127));
      final longEncoded = encode7BitInt(utf8.encode(text).length);
      expect(longEncoded.length, greaterThan(1));
      expect(longEncoded.first & 0x80, 0x80,
          reason: 'الطول فوق 127 يتطلب أكثر من بايت في 7-bit');

      final writer = DotNetBinaryWriter()
        ..writeString(text)
        ..writeString('😀 مرحباً 🌍')
        ..writeString('中文文本')
        ..writeString('мама');
      final reader = DotNetBinaryReader(writer.toBytes());
      expect(reader.readString(), text);
      expect(reader.readString(), '😀 مرحباً 🌍');
      expect(reader.readString(), '中文文本');
      expect(reader.readString(), 'мама');
      expect(reader.remaining, 0);
    });

    test('سلسلة ذات طول 0 بايت تعود فارغة تماماً', () {
      final encoded = encodeDotNetString('');
      expect(encoded, [0x00]);
      final reader = DotNetBinaryReader(encoded);
      expect(reader.readString(), '');
      expect(reader.remaining, 0);
    });
  });

  group('NetworkCrypto (مقارنة حرفية مع تشغيل .NET)', () {
    test('السلوك الافتراضي ممرّر نظراً لمفتاح 31 بايت مثل C# تماماً', () {
      expect(NetworkCrypto.encrypt('Hello AES World'), 'Hello AES World');
      expect(NetworkCrypto.encrypt('مرحبا بالعالم'), 'مرحبا بالعالم');
      expect(NetworkCrypto.encrypt(''), '');
      expect(NetworkCrypto.decrypt('SGVsbG8='), 'SGVsbG8=');
      expect(NetworkCrypto.decrypt(''), '');
    });

    test('AES-256-CBC الحقيقي يطابق نواقل .NET المرجعية', () {
      expect(
        NetworkCrypto.encryptReal('Hello AES World'),
        'HCZ3CtWu5/ChEoIY8zBJxnVICqE8n6hMqL+wIAqwKB8=',
      );
      expect(
        NetworkCrypto.encryptReal('مرحبا بالعالم'),
        'yVt/y4T4d9GlWVg429Uxl9dFwsntmw/zmwavQTC4AqI=',
      );
      expect(
        NetworkCrypto.encryptReal(''),
        'hDrwYhbv5JSNCBlAht1P2g==',
      );
      expect(NetworkCrypto.decryptReal('HCZ3CtWu5/ChEoIY8zBJxnVICqE8n6hMqL+wIAqwKB8='), 'Hello AES World');
      expect(NetworkCrypto.decryptReal('yVt/y4T4d9GlWVg429Uxl9dFwsntmw/zmwavQTC4AqI='), 'مرحبا بالعالم');
    });

    test('نواقل AES-256-CBC إضافية تضبط الثبات عبر إصدارات الحزمة', () {
      expect(
        NetworkCrypto.encryptReal('المفتاح/القيمة: a=b&c=d'),
        'KZjY8makFj65EsoSBRw1HAPdLo1fmP3IRtfi8ZmAy3wJWjYSvhNtAdu8VAVx/85U',
      );
      expect(
        NetworkCrypto.encryptReal('نص طويل يزيد عن كتلة AES واحدة ١٢٣٤٥٦٧٨٩٠'),
        'f3NBe++Cc5qIMidorWx07URK38FgkS9ALoPMnq3ng5Y4fELS5jgGgEFB5FqRmJZys3aOXQx7nJWcw0Sx9nTDN2aqIt8T1nPDU3rpMdaW4yY=',
      );
      expect(
        NetworkCrypto.encryptReal('mixed آسِيي 𝄞 𝌆 and spaces'),
        'Dl7irvQJjqRlxEA5aOA8uPfAviGw2h/XhLbPHtnFY2iWwjlaTAo5tEZQTvlH7XUr',
      );
    });
  });

  group('Ticks .NET', () {
    test('التحويل من وإلى Ticks مع عهد 1970', () {
      final epoch = DateTime.fromMicrosecondsSinceEpoch(0);
      expect(toDotNetTicks(epoch), 621355968000000000);
      final roundTrip = fromDotNetTicks(toDotNetTicks(epoch));
      expect(roundTrip.microsecondsSinceEpoch, 0);
    });

    test('Round-Trip لوقت الآن', () {
      final now = DateTime.now();
      expect(fromDotNetTicks(toDotNetTicks(now)).microsecondsSinceEpoch, now.microsecondsSinceEpoch);
    });
  });

  group('النماذج (بايت-بايت مع ترتيب DataModels.cs)', () {
    test('ChatMessageModel.serialize يطابق ترتيب وعاء BinaryWriter', () {
      final model = ChatMessageModel(
        sender: 'Ahmed',
        recipient: '',
        message: 'hi',
        timestamp: DateTime.fromMicrosecondsSinceEpoch(0),
      );
      final expected = <int>[
        ...encodeDotNetString('Ahmed'),
        ...encodeDotNetString(''),
        ...encodeDotNetString('hi'),
        ...encodeInt64(621355968000000000),
        0x00,
      ];
      expect(model.serialize(), expected);

      final decoded = ChatMessageModel.deserialize(expected);
      expect(decoded.sender, 'Ahmed');
      expect(decoded.recipient, '');
      expect(decoded.message, 'hi');
      expect(decoded.isEncrypted, false);
      expect(decoded.timestamp.microsecondsSinceEpoch, 0);
    });

    test('FileHeaderModel وFileChunkModel Round-Trip', () {
      final header = FileHeaderModel(
        transferId: '1234abcd',
        fileName: 'report.pdf',
        fileSize: 1048576,
        sender: 'Ali',
        recipient: 'Sara',
      );
      final header2 = FileHeaderModel.deserialize(header.serialize());
      expect(header2.transferId, '1234abcd');
      expect(header2.fileName, 'report.pdf');
      expect(header2.fileSize, 1048576);
      expect(header2.sender, 'Ali');
      expect(header2.recipient, 'Sara');
      expect(header2.isPrivate, true);

      final chunk = FileChunkModel(
        transferId: '1234abcd',
        chunkIndex: 3,
        totalChunks: 10,
        data: [0x01, 0x02, 0x03, 0xFF],
      );
      final chunk2 = FileChunkModel.deserialize(chunk.serialize());
      expect(chunk2.chunkIndex, 3);
      expect(chunk2.totalChunks, 10);
      expect(chunk2.data, [0x01, 0x02, 0x03, 0xFF]);
    });

    test('เสียง ذو بيانات فارغة مقابل ممتلئة', () {
      final empty = VoiceMessageModel(sender: 'X', recipient: '', durationSeconds: 0);
      final empty2 = VoiceMessageModel.deserialize(empty.serialize());
      expect(empty2.audioData, isEmpty);
      expect(empty2.durationSeconds, 0);

      final filled = VoiceMessageModel(
        sender: 'X',
        recipient: 'Y',
        durationSeconds: 4,
        audioData: List<int>.generate(64, (i) => i),
      );
      final filled2 = VoiceMessageModel.deserialize(filled.serialize());
      expect(filled2.isPrivate, true);
      expect(filled2.audioData.length, 64);
      expect(filled2.recipient, 'Y');
    });

    test('VideoFrameModel مع وبدون صوت', () {
      final withAudio = VideoFrameModel(
        sender: 'a',
        recipient: 'b',
        frameData: [1, 2, 3],
        audioData: [9, 8, 7],
      );
      final w = VideoFrameModel.deserialize(withAudio.serialize());
      expect(w.frameData, [1, 2, 3]);
      expect(w.audioData, [9, 8, 7]);
      expect(w.sender, 'a');
      expect(w.recipient, 'b');

      final without = VideoFrameModel(sender: 'a', recipient: 'b', frameData: [5]);
      final wo = VideoFrameModel.deserialize(without.serialize());
      expect(wo.frameData, [5]);
      expect(wo.audioData, isEmpty);
    });

    test('CallSignalModel Round-Trip', () {
      final signal = CallSignalModel(sender: 'a', recipient: 'b', signalType: 'ACCEPT');
      final decoded = CallSignalModel.deserialize(signal.serialize());
      expect(decoded.signalType, 'ACCEPT');
      expect(decoded.sender, 'a');
      expect(decoded.recipient, 'b');
    });
  });

  group('التأطير وفك الحزم', () {
    test('framePacket يبني [Type][BigEndian Length][Payload]', () {
      final framed = framePacket(PacketType.publicMessage, [0xDE, 0xAD]);
      expect(framed, [0x04, 0x00, 0x00, 0x00, 0x02, 0xDE, 0xAD]);
    });

    test('PacketDecoder يعالج التجزئة والالتصاق معاً', () {
      final decoder = PacketDecoder();
      final framed1 = framePacket(PacketType.publicMessage, [1, 2]);
      final framed2 = framePacket(PacketType.disconnect, []);
      decoder.write(framed1.sublist(0, 3));
      expect(decoder.tryDecode(), isNull);
      decoder.write(framed1.sublist(3));
      final p1 = decoder.tryDecode();
      expect(p1, isNotNull);
      expect(p1!.type, PacketType.publicMessage);
      expect(p1.payload, [1, 2]);

      decoder.write(framed2);
      final p2 = decoder.tryDecode();
      expect(p2, isNotNull);
      expect(p2!.type, PacketType.disconnect);
      expect(p2.payload, isEmpty);
    });

    test('فك إطار يُغذى بايتاً بايتاً (تمزيق عند كل حد)', () {
      final decoder = PacketDecoder();
      final framed = framePacket(PacketType.privateMessage, [1, 2, 3, 4]);
      for (final byte in framed) {
        expect(decoder.tryDecode(), isNull, reason: 'لا يكتمل قبل البايت الأخير');
        decoder.write([byte]);
      }
      final packet = decoder.tryDecode();
      expect(packet, isNotNull);
      expect(packet!.type, PacketType.privateMessage);
      expect(packet.payload, [1, 2, 3, 4]);
    });

    test('فك إطارين متلاصقين في كتابة واحدة بالتتابع', () {
      final decoder = PacketDecoder();
      final a = framePacket(PacketType.publicMessage, [9, 9]);
      final b = framePacket(PacketType.voiceMessage, [7]);
      decoder.write([...a, ...b]);

      final first = decoder.tryDecode();
      expect(first!.type, PacketType.publicMessage);
      expect(first.payload, [9, 9]);

      final second = decoder.tryDecode();
      expect(second!.type, PacketType.voiceMessage);
      expect(second.payload, [7]);
      expect(decoder.tryDecode(), isNull);
    });

    test('رأس كامل مع حمولة مبتورة يُرجع null ثم يكتمل عند بقية البايتات', () {
      final decoder = PacketDecoder();
      final framed = framePacket(PacketType.callSignal, [0xAA, 0xBB, 0xCC, 0xDD]);
      decoder.write(framed.sublist(0, PacketProtocol.headerSize + 1));
      expect(decoder.tryDecode(), isNull);
      decoder.write(framed.sublist(PacketProtocol.headerSize + 1));
      final packet = decoder.tryDecode();
      expect(packet, isNotNull);
      expect(packet!.type, PacketType.callSignal);
      expect(packet.payload, [0xAA, 0xBB, 0xCC, 0xDD]);
    });

    test('PacketDecoder يرفض حمولة تتجاوز الحد الأمني', () {
      final decoder = PacketDecoder();
      final header = ByteData(5)
        ..setUint8(0, 1)
        ..setUint32(1, 60 * 1024 * 1024, Endian.big);
      decoder.write(header.buffer.asUint8List());
      expect(() => decoder.tryDecode(), throwsFormatException);
    });

    test('حد الحمولة 50MB بالضبط مقبول (لا يُرفض عند بلوغه)', () {
      final decoder = PacketDecoder();
      final header = ByteData(5)
        ..setUint8(0, 1)
        ..setUint32(1, PacketProtocol.maxPayloadSize, Endian.big);
      decoder.write(header.buffer.asUint8List());
      // الحمولة لم تكتمل بعد لكن الطول عند الحد أقصى بدون رفض
      expect(decoder.tryDecode(), isNull);
    });

    test('حد الحمولة يُرفض ابتداءً من 50MB + 1', () {
      final decoder = PacketDecoder();
      final header = ByteData(5)
        ..setUint8(0, 1)
        ..setUint32(1, PacketProtocol.maxPayloadSize + 1, Endian.big);
      decoder.write(header.buffer.asUint8List());
      expect(() => decoder.tryDecode(), throwsFormatException);
    });
  });
}