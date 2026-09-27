import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// خدمة توليد ملف WAV قياسي من بيانات PCM الخام (16-bit أحادي).
Uint8List buildWavBytes(Uint8List pcmData,
    {int sampleRate = 16000, int channels = 1, int bitsPerSample = 16}) {
  final bytes = BytesBuilder();
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);

  void writeString(String s) => bytes.add(asciiBytes(s));
  void writeInt32(int v) =>
      bytes.add(Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.little));
  void writeInt16(int v) =>
      bytes.add(Uint8List(2)..buffer.asByteData().setInt16(0, v, Endian.little));

  writeString('RIFF');
  writeInt32(36 + pcmData.length);
  writeString('WAVE');
  writeString('fmt ');
  writeInt32(16);
  writeInt16(1); // PCM
  writeInt16(channels);
  writeInt32(sampleRate);
  writeInt32(byteRate);
  writeInt16(blockAlign);
  writeInt16(bitsPerSample);
  writeString('data');
  writeInt32(pcmData.length);
  bytes.add(pcmData);
  return bytes.toBytes().buffer.asUint8List();
}

List<int> asciiBytes(String s) => s.codeUnits;

/// تعزيز رقابي للصوت مثل C# ApplyAudioBoost.
Uint8List applyAudioBoost(Uint8List pcm, {double factor = 2.0}) {
  if (pcm.length < 2) return pcm;
  final out = Uint8List(pcm.length);
  final bd = ByteData.view(out.buffer);
  for (var i = 0; i + 1 < pcm.length; i += 2) {
    var s = pcm[i] | (pcm[i + 1] << 8);
    if (s > 0x7FFF) s -= 0x10000;
    var boosted = (s * factor).round();
    boosted = boosted > 0x7FFF
        ? 0x7FFF
        : (boosted < -0x8000 ? -0x8000 : boosted);
    final le = boosted < 0 ? boosted + 0x10000 : boosted;
    bd.setUint8(i, le & 0xFF);
    bd.setUint8(i + 1, (le >> 8) & 0xFF);
  }
  return out;
}

/// تسجيل ملاحظة صوتية كاملة (مثل AudioHelper في C#).
class VoiceNoteRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _started;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<void> start() async {
    if (_recording) return;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw StateError('لا يوجد إذن للوصول إلى المايكروفون');
      }
      final dir = await Directory.systemTemp.createTemp('voice_rec_');
      final path = p.join(dir.path, 'note.wav');
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 32000,
        ),
        path: path,
      );
      _started = DateTime.now();
      _recording = true;
    } catch (e) {
      _recording = false;
      throw StateError('فشل بدء تسجيل الصوت: $e');
    }
  }

  /// يوقف التسجيل ويعيد ملف WAV كامل مع المدة بالثواني (null إذا كان فارغاً).
  Future<({Uint8List wavBytes, int duration})?> stop() async {
    if (!_recording) return null;
    _recording = false;
    final duration = max(1, DateTime.now().difference(_started!).inSeconds);
    try {
      final path = await _recorder.stop();
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return (wavBytes: bytes, duration: duration);
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() => _recorder.dispose();
}

/// مسجل صوت المكالمة الحية (PCM الخام) مثل LiveCallAudioRecorder.
class CallAudioRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  final List<Uint8List> _chunks = [];
  StreamSubscription<Uint8List>? _sub;
  bool _recording = false;
  bool _hasMic = false;

  bool get isRecording => _recording;

  Future<void> start() async {
    if (_recording) return;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _hasMic = false;
        _recording = true;
        return;
      }
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 16000 * 16,
        streamBufferSize: 3200,
      );
      final stream = await _recorder.startStream(config);
      _sub = stream.listen((chunk) {
        _chunks.add(chunk);
      });
      _hasMic = true;
      _recording = true;
    } catch (_) {
      _hasMic = false;
      _recording = true;
    }
  }

  /// يخرج كل البايتات المتراكمة منذ آخر استدعاء (طرف المكالمة يدعمه أيضاً).
  Uint8List? takePendingChunk() {
    if (!_recording || !_hasMic || _chunks.isEmpty) return null;
    final total = _chunks.fold<int>(0, (a, c) => a + c.length);
    final out = Uint8List(total);
    var off = 0;
    for (final c in _chunks) {
      out.setRange(off, off + c.length, c);
      off += c.length;
    }
    _chunks.clear();
    return applyAudioBoost(out, factor: 2.0);
  }

  Future<void> stop() async {
    _recording = false;
    _chunks.clear();
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  Future<void> dispose() => stop();
}

/// مشغل صوت المكالمة الحي من قطع PCM (مثل LiveCallAudioPlayer).
class CallAudioPlayer {
  AudioPlayer? _player;
  bool _playing = false;

  bool get isPlaying => _playing;

  Future<void> start() async {
    if (_playing) return;
    _player ??= AudioPlayer();
    _playing = true;
  }

  Future<void> playChunk(Uint8List pcm) async {
    if (pcm.isEmpty) return;
    await start();
    final wav = buildWavBytes(pcm);
    try {
      await _player?.play(BytesSource(wav.buffer.asUint8List()));
    } catch (_) {}
  }

  Future<void> stop() async {
    _playing = false;
    await _player?.stop();
    await _player?.dispose();
    _player = null;
  }

  Future<void> dispose() => stop();
}

/// واجهة لمصدر إطارات الفيديو (كاميرا حقيقية أو محاكاة تفاعلية مثل C#).
class VideoFrameEmitted {
  VideoFrameEmitted(this.imageBytes, this.isSimulated);
  final Uint8List imageBytes;
  final bool isSimulated;
}

class CameraStreamSource {
  final List<CameraDescription> _availableCameras = [];
  CameraController? _controller;
  Timer? _simulator;
  Timer? _photoTimer;
  StreamController<VideoFrameEmitted>? _frames;
  bool _running = false;
  bool _isSimulated = false;
  bool _capturing = false;
  int _lastEmitMs = 0;
  String? _error;

  Process? _ffmpeg;
  final Encoding _ffmpegEncoding = const Utf8Codec(allowMalformed: true);
  final _mjpegBuffer = <int>[];

  bool get isRunning => _running;
  bool get isSimulated => _isSimulated;
  String? get lastError => _error;

  Stream<VideoFrameEmitted>? get frames => _frames?.stream;

  Future<void> start() async {
    if (_running) return;
    _error = null;
    _frames ??= StreamController.broadcast();

    // 0. Windows: كاميرا حقيقية عالية الدقة عبر ffmpeg (DirectShow -> MJPEG)
    if (Platform.isWindows && await _tryFfmpegCapture()) {
      _running = true;
      _watchdog();
      return;
    }

    // 1. محاولة تشغيل الكاميرا الحقيقية عبر camera_desktop
    try {
      try {
        _availableCameras
          ..clear()
          ..addAll(await availableCameras().timeout(const Duration(seconds: 4)));
        if (_availableCameras.isNotEmpty) {
          _controller = CameraController(
            _availableCameras.first,
            ResolutionPreset.low,
            enableAudio: false,
          );
          await _controller!.initialize().timeout(const Duration(seconds: 5));
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            // Desktop: لا يوجد startImageStream -> التقاط صور دوري بنفس واجهة الإطارات
            _startPhotoCapture();
          } else {
            try {
              // مسار الموبايل: تيار إطارات مباشر (CameraImage -> YUV/JPEG)
              await _controller!.startImageStream(_onCameraImage)
                  .timeout(const Duration(seconds: 3));
            } catch (_) {
              _startPhotoCapture();
            }
          }
          _running = true;
          _watchdog();
          return;
        }
      } catch (_) {
        // جهاز مشغول أو فتح بطيء -> لا نعلّق عند هذا الحاجز
      }
    } catch (e) {
      _error = e.toString();
    }

    _startSimulation();
  }

  // ================= ==== ffmpeg (DirectShow/MJPEG) ============== ==========

  String? _resolveFfmpegPath() {
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final candidate in [
        p.join(exeDir, 'ffmpeg', 'ffmpeg.exe'),
        p.join(exeDir, 'ffmpeg.exe'),
        p.join(Directory.current.path, 'ffmpeg', 'ffmpeg.exe'),
      ]) {
        if (File(candidate).existsSync()) return candidate;
      }
      try {
        final r = Process.runSync('where.exe', ['ffmpeg.exe']);
        if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
          return (r.stdout as String).trim().split('\n').first.trim();
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _detectFfmpegVideoDevice(String ff) async {
    try {
      final r = await Process.run(ff, [
        '-hide_banner',
        '-f', 'dshow',
        '-list_devices', 'true',
        '-i', 'dummy',
      ]);
      final out = (r.stderr as String?) ?? '';
      for (final line in out.split('\n')) {
        if (line.contains('(video)')) {
          final m = RegExp(r'"([^"]+)"').firstMatch(line);
          if (m != null && m.group(1)!.trim().isNotEmpty) {
            return m.group(1)!.trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _tryFfmpegCapture() async {
    final ff = _resolveFfmpegPath();
    if (ff == null) return false;
    final device = await _detectFfmpegVideoDevice(ff);
    if (device == null || device.isEmpty) return false;

    _mjpegBuffer.clear();
    try {
      final proc = await Process.start(ff, [
        '-hide_banner',
        '-loglevel', 'error',
        '-f', 'dshow',
        '-framerate', '30',
        '-video_size', '1280x720',
        '-i', 'video=$device',
        '-an',
        '-c:v', 'copy',
        '-f', 'mjpeg',
        '-',
      ]);
      _ffmpeg = proc;
      proc.stdout.listen((chunk) {
        if (_running) _feedFfmpeg(chunk);
      });
      proc.stderr.transform(_ffmpegEncoding.decoder).listen((t) {
        final trimmed = t.trim();
        if (trimmed.isNotEmpty) _error = trimmed;
      });

      // انتظار أول إطار (أو خروج/فشل) بخيار الاحتياط
      var exited = false;
      proc.exitCode.then((_) => exited = true);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline) && !exited) {
        if (_lastEmitMs != 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (_lastEmitMs == 0) {
        try {
          proc.kill();
        } catch (_) {}
        _ffmpeg = null;
        return false;
      }
      proc.exitCode.then((code) {
        if (_ffmpeg == proc) {
          _error = 'ffmpeg خرج برمز $code';
          _ffmpeg = null;
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _feedFfmpeg(List<int> chunk) {
    _mjpegBuffer.addAll(chunk);
    // قصّ أطر JPEG كاملة (FFD8 ... FFD9) وقُد كل إطار على حدة
    var base = 0;
    while (base + 2 <= _mjpegBuffer.length) {
      final start = _findMarker(base, 0xFF, 0xD8);
      if (start < 0) break;
      final end = _findMarker(start + 2, 0xFF, 0xD9);
      if (end < 0) break;
      final frame = Uint8List.fromList(
          _mjpegBuffer.sublist(start, end + 2));
      _lastEmitMs = DateTime.now().millisecondsSinceEpoch;
      _frames?.add(VideoFrameEmitted(frame, false));
      base = end + 2;
    }
    if (base > 0) {
      if (base < _mjpegBuffer.length) {
        _mjpegBuffer.removeRange(0, base);
      } else {
        _mjpegBuffer.clear();
      }
    }
  }

  int _findMarker(int from, int hi, int lo) {
    for (var i = from; i + 1 < _mjpegBuffer.length; i++) {
      if (_mjpegBuffer[i] == hi && _mjpegBuffer[i + 1] == lo) return i;
    }
    return -1;
  }

  /// حارس أمان: إن لم تُنتج الكاميرا أي إطار خلال 4 ثوانٍ -> تحويل للمحاكاة.
  void _watchdog() {
    Timer(const Duration(seconds: 4), () async {
      if (!_running || _isSimulated) return;
      if (DateTime.now().millisecondsSinceEpoch - _lastEmitMs > 3500) {
        _error = 'الكاميرا لا تصلها إطارات - تحويل لوضع المحاكاة';
        _photoTimer?.cancel();
        _photoTimer = null;
        try {
          _ffmpeg?.kill();
        } catch (_) {}
        _ffmpeg = null;
        try {
          await _controller?.dispose();
        } catch (_) {}
        _controller = null;
        _startSimulation();
      }
    });
  }

  Future<void> _startSimulation() async {
    _isSimulated = true;
    _running = true;
    _lastEmitMs = DateTime.now().millisecondsSinceEpoch;
    _simulator = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final frame = await _renderSimulatedFrame();
      if (frame != null && _running) {
        _lastEmitMs = now;
        _frames?.add(frame);
      }
    });
  }

  void _startPhotoCapture() {
    _photoTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      final camera = _controller;
      if (!_running || camera == null || _capturing) return;
      _capturing = true;
      try {
        final shot = await camera.takePicture();
        final bytes = await shot.readAsBytes();
        if (bytes.isNotEmpty) {
          _lastEmitMs = DateTime.now().millisecondsSinceEpoch;
          _frames?.add(VideoFrameEmitted(bytes, false));
        }
        try {
          await File(shot.path).delete();
        } catch (_) {}
      } catch (_) {}
      _capturing = false;
    });
  }

  DateTime? _lastRealFrameAt;

  Future<void> _onCameraImage(CameraImage image) async {
    if (!_running) return;
    final now = DateTime.now();
    final last = _lastRealFrameAt;
    if (last != null && now.difference(last).inMilliseconds < 200) return;
    _lastRealFrameAt = now;
    try {
      final jpg = _yuv420ToJpeg(image);
      if (_running) {
        _lastEmitMs = DateTime.now().millisecondsSinceEpoch;
        _frames?.add(VideoFrameEmitted(jpg, false));
      }
    } catch (_) {}
  }

  Uint8List _yuv420ToJpeg(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final imgImage = img.Image(width: width, height: height);
    final planes = image.planes;

    // Y / U / V planes (NV21-like -> YUV420)
    final yPlane = planes[0].bytes;
    var uPlane = planes.length > 1 ? planes[1].bytes : null;
    var vPlane = planes.length > 2 ? planes[2].bytes : null;
    if (uPlane == null || vPlane == null) {
      // بعض الكاميرات تقدم U وV داخل المستوى الثاني نفسه (NV21)
      uPlane = planes.length > 1 ? planes[1].bytes : Uint8List(0);
      vPlane = planes.length > 2 ? planes[2].bytes : Uint8List(0);
    }
    final uRowLength = planes[1].width ?? (width ~/ 2);
    final yPitch = planes[0].bytesPerRow;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yOffset = (y * yPitch) + x;
        final yVal = yPlane[yOffset];
        final uvIndex = (y ~/ 2) * uRowLength + (x ~/ 2);
        int uVal = 128;
        int vVal = 128;
        if (uvIndex < uPlane.length) uVal = uPlane[uvIndex];
        if (uvIndex < vPlane.length) vVal = vPlane[uvIndex];
        _yuvToRgb(yVal, uVal, vVal, (r, g, b) {
          imgImage.setPixelRgb(x, y, r, g, b);
        });
      }
    }
    final resized = width > 480 ? img.copyResize(imgImage, width: 480) : imgImage;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 60));
  }

  void _yuvToRgb(int y, int u, int v, void Function(int r, int g, int b) out) {
    var c = y - 16;
    var d = u - 128;
    var e = v - 128;
    var r = (298 * c + 409 * e + 128) >> 8;
    var g = (298 * c - 100 * d - 208 * e + 128) >> 8;
    var b = (298 * c + 516 * d + 128) >> 8;
    r = r.clamp(0, 255);
    g = g.clamp(0, 255);
    b = b.clamp(0, 255);
    out(r, g, b);
  }

  Future<VideoFrameEmitted?> _renderSimulatedFrame() async {
    try {
      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);
      const w = 320.0, h = 240.0;
      final rect = Rect.fromLTWH(0, 0, w, h);

      final gradient = ui.Gradient.linear(
        Offset.zero,
        const Offset(w, h),
        [const Color(0xFF0F172A), const Color(0xFF1E293B)],
      );
      canvas.drawRect(rect, Paint()..shader = gradient);

      final animTick = DateTime.now().millisecondsSinceEpoch ~/ 60;
      final centerX = w / 2;
      final centerY = h / 2 - 15;

      canvas.drawCircle(Offset(centerX, centerY - 2), 30, Paint()..color = const Color(0xFF4682B4));
      canvas.drawOval(Rect.fromCenter(center: Offset(centerX, centerY + 68), width: 110, height: 65), Paint()..color = const Color(0xFF6495ED));

      final radarPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF2ECC71);
      canvas.drawCircle(Offset(centerX, centerY + 20), 65, radarPaint);
      final angle = (animTick % 360) * pi / 180;
      canvas.drawLine(Offset(centerX, centerY + 20), Offset(centerX + 65 * cos(angle), centerY + 20 + 65 * sin(angle)), radarPaint);

      // مؤشر صوتي متحرك
      for (var i = 0; i < 7; i++) {
        final bar = 6 +
            (sin((animTick * 0.2) + (i * 0.8)) * 10 + 10).toInt();
        canvas.drawRect(
          Rect.fromLTWH(12 + (i * 7), h - 45 - bar, 5, bar.toDouble()),
          Paint()..color = const Color(0xFF3498DB),
        );
      }

      canvas.drawRect(
        Rect.fromLTWH(0, h - 34, w, 34),
        Paint()..color = const Color(0xBE000000),
      );
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '🔴 LIVE CAM STREAM',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, const Offset(8, h - 27));
      final timeStr = _formatTime(DateTime.now());
      final timePainter = TextPainter(
        text: TextSpan(
          text: timeStr,
          style: const TextStyle(color: Color(0xFF90EE90), fontSize: 12, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      timePainter.paint(canvas, Offset(w - timePainter.width - 8, h - 27));

      final image = await pictureRecorder.endRecording().toImage(w.toInt(), h.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return VideoFrameEmitted(data!.buffer.asUint8List(), true);
    } catch (_) {
      return null;
    }
  }

  String _formatTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';

  Future<void> stop() async {
    _running = false;
    _lastRealFrameAt = null;
    _lastEmitMs = 0;
    _capturing = false;
    _mjpegBuffer.clear();
    try {
      _ffmpeg?.kill();
    } catch (_) {}
    _ffmpeg = null;
    _simulator?.cancel();
    _simulator = null;
    _photoTimer?.cancel();
    _photoTimer = null;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _isSimulated = false;
  }

  Future<void> dispose() => stop();
}