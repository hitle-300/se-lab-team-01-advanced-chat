<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/tools/pub/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

TODO: Put a short description of the package here that helps potential users
know whether this package might be useful for them.

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder.

```dart
const like = 'sample';
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to
contribute to the package, how to file issues, what response they can expect
from the package authors, and more.

---

## مساهماتي (الطالب C — الوحدة المشتركة)

ينفّذ هذا العمل الطالب المسؤول عن «الحزمة المشتركة» (shared-protocol):

- توثيق البروتوكول الكامل في `shared/docs/PROTOCOL.md`:
  - أنواع الحزم الـ13 (مطابقة PacketType.cs)
  - هيكل التغليف والحدود الأمنية (50MB بالضبط مقبول وما فوق مرفوض)
  - مخطط المصافحة وترتيب الدمج C ← B ← A
  - نتائج فحص التوافق البايتي مع نظير C# .NET
- اختبارات شاملة في `shared/test/shared_test.dart`:
  - حد الحمولة 50MB بالضبط وأعلى منها
  - فريمات مبتورة وملتصقة لـ PacketDecoder
  - نصوص متعددة البايت وفراغات في ترميز 7-bit/BinaryWriter
  - نواقل AES-256-CBC إضافية تثبّت التوافق عبر إصدارات الحزمة
- أداة `shared/tool/wire_dump.dart` لمقارنة البايتات مع التقاط .NET.
- اختبار اتصال بأرقام عربية وأحرف غير ASCII في
  `client/test/client_engine_test.dart`.
