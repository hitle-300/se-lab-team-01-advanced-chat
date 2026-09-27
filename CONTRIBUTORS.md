# المساهمون — مشروع المحادثة الشبكية (Flutter)

> مستند تنسيقي: أعدّه المنسّق بعد اكتمال الدمج، اعتماداً على سجل `git` الفعلي
> وليس على النسخ اليدوي. كل رقم أدناه قابل للتحقق بأمر `git log`.

## الحالة النهائية

الفرع `master` يحتوي **46 commit** فوق الأساس `967abe2`:

- **42 commit عمل**: الطالب A ‎11 · الطالب B ‎20 · الطالب C ‎11
- **4 commits دمج** (PRs #1، #3، #4، #5)
- **16 ملفاً** معدَّلاً: ‎+972 سطر / ‎-61 سطر

## توزيع الملكية (مستخرج من `git log`)

| العضو | الحساب على GitHub | الفرع | commits | الملفات التي أنشأها أو عدّلها |
|---|---|---|---|---|
| الطالب A | `hitle-300` (MOHAMED SADEQ ALHADRMI) | `client-chat` | 11 | `client/lib/main.dart` · `client/test/widget_test.dart` · `client/pubspec.yaml` · `client/README.md` |
| الطالب B | `zyadalsmawy810-create` | `server-db` | 20 | `server/lib/server_config.dart` · `server/lib/admin_page.dart` · `server/lib/async_server.dart` · `server/lib/database_viewer_page.dart` · `server/test/server_engine_test.dart` · `server/server_config.json` · `server/README.md` |
| الطالب C | `aalsmawy644-collab` | `shared-protocol` | 11 | `shared/test/shared_test.dart` · `shared/docs/PROTOCOL.md` · `shared/tool/wire_dump.dart` · `client/test/client_engine_test.dart` · `shared/README.md` |

**تصحيح مهم:** الملفات `client/lib/async_client.dart` و`client/lib/screens/demo_screens.dart`
و`client/lib/services/hardware_services.dart` و`shared/lib/*` هي **هيكل المشروع الأساسي**
الموجود قبل عمل الطلاب، ولم يعدّلها أي طالب.

## ملخص مساهمة كل عضو

### الطالب A — وحدة العميل (11 commit)
- شاشة الاتصال (IP + المنفذ + الاسم) وواجهة المحادثة في `client/lib/main.dart`.
- اختبار واجهة (widget test) + قسم "مساهماتي" في `client/README.md`.
- إضافة الاعتماد المطلوب في `client/pubspec.yaml`.

### الطالب B — وحدة الخادم (20 commit)
1. `server/server_config.json` + `server/lib/server_config.dart`: قراءة/حفظ IP والمنفذ.
2. `server/lib/admin_page.dart`: شريط حالة + أزرار تحكم الخادم.
3. `server/lib/async_server.dart`: تشغيل/إيقاف + سجل `logs/Activity_<date>.log`.
4. `server/lib/database_viewer_page.dart`: تصدير الجداول CSV + فرز وترقيم رسائل المستخدمين.
5. `server/test/server_engine_test.dart`: 26 اختباراً للمحرك.
6. `server/README.md`: التوثيق وقسم "مساهماتي".
7. **ملاحظة أمانة:** 9 من هذه الـ 20 commit هي حذف ثم إعادة إضافة لنفس الكود (صافي
   التغيير = صفر)؛ رفعها الطالب نفسه بعد دمج فروعه فلم تضف محتوى جديداً.

### الطالب C — البروتوكول المشترك (11 commit)
1. `shared/test/shared_test.dart`: 28 اختباراً (التأطير، فك الحزم، الحدود الأمنية، التشفير).
2. `shared/docs/PROTOCOL.md`: توثيق البروتوكول.
3. `shared/tool/wire_dump.dart`: أداة تحليل الحزم.
4. `client/test/client_engine_test.dart`: اختبار محرك الاتصال.
5. `shared/README.md`: التوثيق وقسم "مساهماتي".

## نتائج الفحص الفعلي

| الوحدة | الاختبارات | `flutter analyze` |
|---|---|---|
| `shared` | 28 / 28 ناجح | لا مشاكل |
| `server` | 26 / 26 ناجح | لا مشاكل |
| `client` | 20 / 21 | لا مشاكل |

الفاشل الوحيد: `client/test/screenshot_capture_test.dart` — لقطة "عارض قاعدة البيانات"، لأن
عمود `LastSeen` يُخزَّن بـ `DateTime.now()` وتُعرض القيمة الخام، فتتغير اللقطة مع كل تشغيل.

**تشغيل فعلي عبر TCP تم التحقق منه:** مصافحة عميلين · بث قائمة المستخدمين · رسالة نصية
عربية · نقل ملف 293 كيلوبايت · قطع الاتصال وإعادة الاتصال · إنشاء سجل النشاط.

## إثبات المساهمة
- 46 commit على `master`، وكل commit مربوط بحسابه على GitHub (صفر commit غير مربوط).
- 4 دمجات عبر PRs #1، #3، #4، #5 بزر *Create a merge commit* (بدون Squash).
- كل عضو قادر على شرح كل بند عمل به أمام المشرف.

## عيوب معروفة (مُبلَّغ عنها ولم تُصلَح عمداً)
1. `server/lib/async_server.dart`: كتابة سجل النشاط تجري بشكل غير متسلسل (`unawaited`)،
   فتتداخل الكتابات أحياناً ويُفسد ترميز حروف العربية في السجل.
2. `server/lib/async_server.dart`: سطر عناوين الشبكة يسجّل المنفذ المطلوب بدل المنفذ الفعلي
   الم绑定 (يظهر `(المنفذ: 0)` عند التشغيل على منفذ عشوائي).
