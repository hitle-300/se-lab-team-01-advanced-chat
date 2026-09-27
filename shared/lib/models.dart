import 'dotnet_binary.dart';

const int dotNetEpochTicks = 621355968000000000;
const int ticksPerMicrosecond = 10;

int toDotNetTicks(DateTime dateTime) =>
    dotNetEpochTicks + dateTime.microsecondsSinceEpoch * ticksPerMicrosecond;

DateTime fromDotNetTicks(int ticks) =>
    DateTime.fromMicrosecondsSinceEpoch((ticks - dotNetEpochTicks) ~/ ticksPerMicrosecond);

class ChatMessageModel {
  ChatMessageModel({
    this.sender = '',
    this.recipient = '',
    this.message = '',
    DateTime? timestamp,
    this.isEncrypted = false,
  }) : timestamp = timestamp ?? DateTime.now();

  String sender;
  String recipient;
  String message;
  DateTime timestamp;
  bool isEncrypted;

  bool get isPrivate => recipient.isNotEmpty;

  List<int> serialize() {
    final writer = DotNetBinaryWriter()
      ..writeString(sender)
      ..writeString(recipient)
      ..writeString(message)
      ..writeInt64(toDotNetTicks(timestamp))
      ..writeByte(isEncrypted ? 1 : 0);
    return writer.toBytes();
  }

  static ChatMessageModel deserialize(List<int> data) {
    final reader = DotNetBinaryReader(data);
    final model = ChatMessageModel(
      sender: reader.readString(),
      recipient: reader.readString(),
      message: reader.readString(),
      timestamp: fromDotNetTicks(reader.readInt64()),
    );
    if (reader.remaining > 0) {
      model.isEncrypted = reader.readByte() != 0;
    }
    return model;
  }
}

class FileHeaderModel {
  FileHeaderModel({
    this.transferId = '',
    this.fileName = '',
    this.fileSize = 0,
    this.sender = '',
    this.recipient = '',
  });

  String transferId;
  String fileName;
  int fileSize;
  String sender;
  String recipient;

  bool get isPrivate => recipient.isNotEmpty;

  List<int> serialize() {
    final writer = DotNetBinaryWriter()
      ..writeString(transferId)
      ..writeString(fileName)
      ..writeInt64(fileSize)
      ..writeString(sender)
      ..writeString(recipient);
    return writer.toBytes();
  }

  static FileHeaderModel deserialize(List<int> data) {
    final reader = DotNetBinaryReader(data);
    return FileHeaderModel(
      transferId: reader.readString(),
      fileName: reader.readString(),
      fileSize: reader.readInt64(),
      sender: reader.readString(),
      recipient: reader.readString(),
    );
  }
}

class FileChunkModel {
  FileChunkModel({
    this.transferId = '',
    this.chunkIndex = 0,
    this.totalChunks = 0,
    this.data = const <int>[],
  });

  String transferId;
  int chunkIndex;
  int totalChunks;
  List<int> data;

  List<int> serialize() {
    final writer = DotNetBinaryWriter()
      ..writeString(transferId)
      ..writeInt32(chunkIndex)
      ..writeInt32(totalChunks)
      ..writeInt32(data.length);
    if (data.isNotEmpty) {
      writer.writeBytes(data);
    }
    return writer.toBytes();
  }

  static FileChunkModel deserialize(List<int> data) {
    final reader = DotNetBinaryReader(data);
    return FileChunkModel(
      transferId: reader.readString(),
      chunkIndex: reader.readInt32(),
      totalChunks: reader.readInt32(),
      data: reader.readBytes(reader.readInt32()),
    );
  }
}

class VoiceMessageModel {
  VoiceMessageModel({
    this.sender = '',
    this.recipient = '',
    this.durationSeconds = 0,
    this.audioData = const <int>[],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String sender;
  String recipient;
  int durationSeconds;
  List<int> audioData;
  DateTime timestamp;

  bool get isPrivate => recipient.isNotEmpty;

  List<int> serialize() {
    final writer = DotNetBinaryWriter()
      ..writeString(sender)
      ..writeString(recipient)
      ..writeInt32(durationSeconds)
      ..writeInt64(toDotNetTicks(timestamp))
      ..writeInt32(audioData.length);
    if (audioData.isNotEmpty) {
      writer.writeBytes(audioData);
    }
    return writer.toBytes();
  }

  static VoiceMessageModel deserialize(List<int> data) {
    final reader = DotNetBinaryReader(data);
    return VoiceMessageModel(
      sender: reader.readString(),
      recipient: reader.readString(),
      durationSeconds: reader.readInt32(),
      timestamp: fromDotNetTicks(reader.readInt64()),
      audioData: reader.readBytes(reader.readInt32()),
    );
  }
}

class VideoFrameModel {
  VideoFrameModel({
    this.sender = '',
    this.recipient = '',
    this.frameData = const <int>[],
    this.audioData = const <int>[],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String sender;
  String recipient;
  List<int> frameData;
  List<int> audioData;
  DateTime timestamp;

  bool get isPrivate => recipient.isNotEmpty;

  List<int> serialize() {
    final writer = DotNetBinaryWriter()
      ..writeString(sender)
      ..writeString(recipient)
      ..writeInt64(toDotNetTicks(timestamp))
      ..writeInt32(frameData.length);
    if (frameData.isNotEmpty) {
      writer.writeBytes(frameData);
    }
    writer.writeInt32(audioData.length);
    if (audioData.isNotEmpty) {
      writer.writeBytes(audioData);
    }
    return writer.toBytes();
  }

  static VideoFrameModel deserialize(List<int> data) {
    final reader = DotNetBinaryReader(data);
    final model = VideoFrameModel(
      sender: reader.readString(),
      recipient: reader.readString(),
      timestamp: fromDotNetTicks(reader.readInt64()),
      frameData: reader.readBytes(reader.readInt32()),
    );
    if (reader.remaining > 0) {
      final audioLength = reader.readInt32();
      if (audioLength > 0) {
        model.audioData = reader.readBytes(audioLength);
      }
    }
    return model;
  }
}

class CallSignalModel {
  CallSignalModel({
    this.sender = '',
    this.recipient = '',
    this.signalType = '',
  });

  String sender;
  String recipient;
  String signalType;

  List<int> serialize() {
    final writer = DotNetBinaryWriter()
      ..writeString(sender)
      ..writeString(recipient)
      ..writeString(signalType);
    return writer.toBytes();
  }

  static CallSignalModel deserialize(List<int> data) {
    final reader = DotNetBinaryReader(data);
    return CallSignalModel(
      sender: reader.readString(),
      recipient: reader.readString(),
      signalType: reader.readString(),
    );
  }

  CallSignalModel copyWith({String? sender, String? recipient, String? signalType}) {
    return CallSignalModel(
      sender: sender ?? this.sender,
      recipient: recipient ?? this.recipient,
      signalType: signalType ?? this.signalType,
    );
  }
}