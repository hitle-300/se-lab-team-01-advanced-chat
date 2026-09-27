import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client_app/async_client.dart';
import 'package:client_app/main.dart';
import 'package:shared/shared.dart';

void main() {
  testWidgets('شاشة الاتصال تعرض عناصرها الأساسية', (WidgetTester tester) async {
    await tester.pumpWidget(const ClientApp());

    expect(find.text('عميل المحادثة الشبكي'), findsOneWidget);
    expect(find.text('عنوان IP:'), findsOneWidget);
    expect(find.text('رقم المنفذ:'), findsOneWidget);
    expect(find.text('اسم المستخدم:'), findsOneWidget);
    expect(find.text('اتصال بالخادم'), findsOneWidget);
    expect(find.text('جاهز للاتصال بالخادم عبر السوكيت.'), findsOneWidget);
    expect(find.text('إعادة محاولة الاتصال'), findsNothing);

    await tester.enterText(
        find.byType(TextField).first, '192.168.1.10');
    await tester.pump();
    final ipField = tester.widget<TextField>(find.byType(TextField).first);
    expect(ipField.controller!.text, '192.168.1.10');
  });

  test('طابع الوقت العربي يحوّل الأرقام إلى أرقام عربية', () {
    expect(formatArabicTime(DateTime(2026, 1, 2, 3, 4, 5)), '٠٣:٠٤:٠٥');
    expect(formatArabicTime(DateTime(2026, 6, 15, 23, 59, 59)), '٢٣:٥٩:٥٩');
    expect(formatArabicTime(DateTime(2026, 6, 15, 10, 0, 9)), '١٠:٠٠:٠٩');
  });

  testWidgets('الحالة الفارغة تظهر رسائل إرشادية للمتصلين والرسائل والملفات',
      (WidgetTester tester) async {
    final client = _EmptyClient();
    client.username = 'أحمد';
    client.serverIp = '192.168.128.20';
    client.serverPort = 5000;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ChatScreen(client: client),
      ),
    ));

    expect(find.text('لا يوجد متصلون'), findsOneWidget);

    await tester.tap(find.text('المحادثة العامة'));
    await tester.pump();
    expect(find.text('لا توجد رسائل بعد'), findsOneWidget);
    expect(find.text('لا توجد ملفات مستلمة أو مرسلة بعد'), findsOneWidget);
  });

  testWidgets('الرسائل المشفرة تعرض شارة القفل', (WidgetTester tester) async {
    final client = _EmptyClient();
    client.username = 'أحمد';
    client.serverIp = '192.168.128.20';
    client.serverPort = 5000;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ChatScreen(client: client),
      ),
    ));

    await tester.tap(find.text('المحادثة العامة'));
    await tester.pump();
    client.onPublicMessage!(ChatMessageModel(
      sender: 'سارة',
      message: 'رسالة سرية مشفرة',
      isEncrypted: true,
    ));
    await tester.pump();

    expect(find.text('مشفر'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsWidgets);
  });
}

class _EmptyClient extends AsyncClient {
  @override
  void disconnect([String? reason]) {}
}