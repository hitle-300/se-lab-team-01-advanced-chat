import 'package:flutter/material.dart';

const List<String> kickReasons = [
  'مخالفة قواعد المحادثة والآداب العامة',
  'إرسال رسائل أو ملفات مزعجة (Spam)',
  'انتحال شخصية أو استخدام اسم غير لائق',
  'أسباب إدارية وأمنية خاصة بالشبكة',
  'سبب مخصص (اكتب في الصندوق أدناه)',
];

/// معادل KickDialog.cs: نافذة تأكيد طرد وحظر العميل لمدة 5 دقائق.
Future<String?> showKickDialog(BuildContext context, String username) async {
  var selectedIndex = 0;
  var customText = kickReasons.first;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            title: const Text('طرد وحظر العميل من الخادم',
                style: TextStyle(fontSize: 17)),
            content: SizedBox(
              width: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تأكيد طرد العميل: [$username] وحظره لمدة 5 دقائق',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  const Text('اختر سبب الطرد من القائمة:'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: selectedIndex,
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < kickReasons.length; i++)
                        DropdownMenuItem(value: i, child: Text(kickReasons[i])),
                    ],
                    onChanged: (value) {
                      setLocalState(() {
                        selectedIndex = value!;
                        if (selectedIndex < 4) {
                          customText = kickReasons[selectedIndex];
                        } else {
                          customText = '';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('نص رسالة الطرد التي ستظهر للعميل:'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: TextEditingController(text: customText),
                    maxLines: 2,
                    onChanged: (value) {
                      customText = value;
                    },
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '⚠️ ملاحظة: لن يتمكن هذا العميل من إعادة الاتصال إلا بعد انقضاء 5 دقائق كاملة.',
                    style: TextStyle(
                        color: Color(0xFFC0392B),
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC0392B),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final res = customText.trim();
                  Navigator.of(dialogContext)
                      .pop(res.isEmpty ? kickReasons[selectedIndex] : res);
                },
                child: const Text('تنفيذ الطرد والحظر (5 دقائق)'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إلغاء'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// معادل PromptDialog.cs: نافذة إدخال نص (تُستخدم للإشعارات الإدارية).
Future<String?> showPromptDialog(
  BuildContext context, {
  required String title,
  required String prompt,
  String defaultValue = '',
}) {
  final controller = TextEditingController(text: defaultValue);

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(prompt),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('موافق'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      );
    },
  );
}