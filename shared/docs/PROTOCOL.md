# PROTOCOL.md — مواصفة بروتوكول الشبكة المشترك

هذه الوثيقة تُوثّق صيغة البايتات الثنائية المستخدمة بين العميل Flutter والخادم
(نظيره C# .NET) بحيث يستطيع كلا الطرفين تبادل الرسائل دون أي توافق غير صريح.

## 1) هيكل التغليف العام (Packet Framing)

كل رسالة تُغلَّف كالتالي، بما يتطابق مع `BinaryWriter` في C#:

```
[ 0 ]  بايت نوع الحزمة      → PacketType.byte (1..13)
[1..4] الطول بالبايتات      → uint32 بأسلوب Big-Endian (بلا مفاتيح، كما كتبه .NET)
[5..]  محتوى الحزمة         → Payload (تسلسل الحقول وفق النموذج أدناه)
```

- `headerSize = 5` بايتات.
- `maxChunkSize = 32 * 1024` بايت (أقصى قطعة ملف مرسلة/واحدة).
- `maxPayloadSize = 50 * 1024 * 1024` بايت (أقصى حمولة مقبولة؛ 50MB بالضبط مقبول،
  وما زاد يُرفض فوراً بـ FormatException).

## 2) أنواع الحزم (مطابقة PacketType.cs)

| الرقم | الحزمة            | المعنى                                          |
|------:|-------------------|-------------------------------------------------|
| 1     | connectRequest    | طلب اتصال باسم مستخدم                           |
| 2     | connectResponse   | رد نجاح/رفض الاتصال                              |
| 3     | userListUpdate    | تحديث قائمة المستخدمين المتصلين                  |
| 4     | publicMessage     | رسالة عامة                                      |
| 5     | privateMessage    | رسالة خاصة                                      |
| 6     | fileMetadata      | معلومات بدء نقل ملف                             |
| 7     | fileChunk         | قطعة من الملف                                    |
| 8     | fileComplete      | إتمام نقل ملف                                    |
| 9     | disconnect        | إنهاء الاتصال/إيقاف الخادم                       |
| 10    | kickNotice        | إشعار طرد العميل                                 |
| 11    | voiceMessage      | رسالة صوتية                                      |
| 12    | videoFrame        | إطار فيديو (مع صوت اختياري)                      |
| 13    | callSignal        | إشارة مكالمة (START / ACCEPT / REJECT / END)     |

## 3) ترتيب حقول الحقول المشفرة (نماذج DataModels.cs)

القيم غير النصية تُكتب Little-Endian كما في .NET، والنصوص بطول 7-bit يتبعه UTF-8:

| النموذج            | الحقول بالتسلسل                                          |
|--------------------|----------------------------------------------------------|
| ChatMessageModel   | sender, recipient, message (7-bit+UTF8) — timestamp (Int64 Ticks) — isEncrypted (byte) |
| FileHeaderModel    | transferId, fileName, sender, recipient — fileSize (Int64) — isPrivate (byte) |
| FileChunkModel     | transferId — chunkIndex (Int32) — totalChunks (Int32) — data (bytes) |
| VoiceMessageModel  | sender, recipient — durationSeconds (Int32) — audioData (bytes) |
| VideoFrameModel    | sender, recipient — frameData (bytes) — audioData (bytes) |
| CallSignalModel    | sender, recipient, signalType |

## 4) التوافق مع نص C#

- `encodeDotNetString` = `BinaryWriter.Write(string)`: طول 7-bit ثم بايتات UTF-8.
- `encodeInt64` = `BinaryWriter.Write(long)`.
- التشفير AES-256-CBC: عند فشل المفتاح (31 بايت في C# الأسطوري) يجري **passthrough**
  وإرجاع النص كما هو — وهذا متفق عليه بين الطرفين فعلاً.

## 5) مصافحة الاتصال (Handshake)

```
العميل Flutter                          الخادم C# .NET
   |                                        |
   |-- connectRequest (1) [name=UTF-8] ---->|
   |                                        |  هل الاسم مستخدم؟ استبعاد؟
   |<---- connectResponse (2) -------------|  نعم/حظر
   |  [قائمة المستخدمين]                    |
   |<-- userListUpdate (3) [بعد كل دخول] ---|
   |                                        |
   |-- publicMessage (4)/privateMessage (5) |
   |-- fileMetadata (6) → fileChunk (7)...  |
   |<--------------- fileComplete (8) ----->|
   |-- voiceMessage (11)/videoFrame (12)    |
   |-- callSignal (13) START/ACCEPT/END     |
   |                                        |
   |-- disconnect (9) / <-kickNotice (10)-  |
```

- عند تكرار اسم المستخدم المتصل: `connectResponse` برفض + نص خطأ عربي، ثم إغلاق.
- ترتيب الالتحاق بالمجموعات والبث: القائمة تُرسل للمستخدم الجديد أولاً ثم
  `userListUpdate` لكل المستخدمين الآخرين (باستثناء صاحب الحزمة).

## 6) ترتيب الدمج والاندماج في المستودع

أطراف المشروع (لطلاب الفريق الثلاثة):

- **A = العميل Flutter** (منسّق المستودع).
- **B = الخادم C# .NET**.
- **C = الحزمة المشتركة `shared/`** (البروتوكول، الترميز، النماذج).

ترتيب دمج الفروع (إلزامي واختباري):

1. **C أولاً** (branch `shared-protocol`) — يضع الأساس المشترك.
2. **B ثانياً** (branch `server-db`) — يعتمد على حزمة C.
3. **A أخيراً** (branch `client-chat`) — يعتمد على حزمة C + خادم B.

الدمج بزر **Create a merge commit** (لا Squash) حتى يحتفظ كل فرع بتاريخه.

## 7) نتائج توافق البايتات (Byte-Compat)

الاختبارات في `shared/test/shared_test.dart` تثبّت النتائج التالية لتجنّب الانحراف:

- `framePacket(publicMessage, [0xDE, 0xAD])` = `04 00 00 00 02 DE AD`.
- كتابة `"Hello"` = `05 48 65 6C 6C 6F`.
- `"مرحباً"` تُكتب UTF-8 بطول 7-bit يحسب البايتات وليس الأحرف.
- Chinese/Cyrillic/emoji تُفكّ وتُعاد بنفس البايتات.
- نواقل AES-256-CBC غير قابلة للتغير عبر إصدارات الحزمة (ضمان ثبات بين الجانبين).
- حد 50MB بالضبط مقبول، و`50MB+1` مرفوض فوراً.
- أداة التحقق: `dart run shared/tool/wire_dump.dart` تطبع البايتات لمقارنتها
  مع تسجيل واضح من نظير .NET.