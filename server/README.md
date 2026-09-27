# server_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## مساهماتي (الطالب B — الوحدة: الخادم)

ينفّذ هذا العمل الطالب المسؤول عن وحدة الخادم (server-db):

- نموذج `ServerConfig` في `server/lib/server_config.dart` مع ملف
  `server/server_config.json` الافتراضي، وتعبئة المنفذ/IP عند فتح لوحة
  الإدارة وحفظ الإعدادات عند الضغط على «تشغيل الخادم».
- سجل أحداث دائم: إنشاء مجلد `logs/` تلقائياً عند تشغيل الخادم، وكتابة
  كل حدث في `logs/Activity_<التاريخ>.log` من `async_server.dart`.
- تصدير كل الجداول CSV دفعة واحدة من `database_viewer_page.dart` مع
  اختيار المجلد ورسالة نجاح تُظهر عدد الصفوف لكل جدول.
- فرز الرسائل (الأحدث/الأقدم) مع ترقيم صفحات لجدول الرسائل.
- اختبارات محرك:
  - «انتهاء مدة الحظر يسمح بإعادة الاتصال».
  - «انقطاع عميل أثناء نقل ملف ثم إعادة اتصال سليمة».
