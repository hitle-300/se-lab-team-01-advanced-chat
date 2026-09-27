import 'package:flutter/material.dart';

const Color _kBackground = Color(0xFF0F172A);
const Color _kPrimary = Color(0xFF1E88E5);
const Color _kAccent = Color(0xFF2ECC71);
const Color _kLightBlue = Color(0xFF4FC3F7);

class RtlShell extends StatelessWidget {
  const RtlShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.rtl, child: child);
  }
}

class ScreensGalleryScreen extends StatelessWidget {
  const ScreensGalleryScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RtlShell(child: screen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, Color, String, String, Widget Function())>[
      (
        Icons.forum_rounded,
        _kPrimary,
        'الشاشة الرئيسية (وصف التطبيق)',
        'ترحيب + مميزات + حساب المستخدم',
        () => const WelcomeScreen()
      ),
      (
        Icons.login_rounded,
        _kAccent,
        'تسجيل الدخول',
        'اسم مستخدم + كلمة مرور',
        () => const LoginScreen()
      ),
      (
        Icons.person_add_alt_1_rounded,
        _kLightBlue,
        'إنشاء حساب جديد',
        'نموذج تسجيل عميل جديد',
        () => const RegisterScreen()
      ),
      (
        Icons.settings_rounded,
        const Color(0xFFFB8C00),
        'الإعدادات والملف الشخصي',
        'تخصيص المظهر والإشعارات واللغة',
        () => const SettingsScreen()
      ),
      (
        Icons.videocam_rounded,
        const Color(0xFFE53935),
        'مكالمة الفيديو',
        'واجهة مكالمة مرئية تفاعلية (تجريبية)',
        () => const VideoCallDemoScreen()
      ),
      (
        Icons.notifications_rounded,
        const Color(0xFF8E24AA),
        'الإشعارات والتحديثات',
        'سجل التنبيهات الواردة',
        () => const NotificationsScreen()
      ),
    ];

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('معرض الواجهات'),
        backgroundColor: _kBackground,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final (icon, color, title, subtitle, builder) = entries[index];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(context, builder()),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: color.withValues(alpha: 0.18),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 3),
                          Text(subtitle,
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_left, color: color),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('عن التطبيق'),
        backgroundColor: _kBackground,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 130,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Center(
                    child: Icon(Icons.forum_rounded, size: 64, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'عميل المحادثة الشبكي',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'مراسلة فورية تصل إلى كل جهاز متصل',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 14),
                ),
                const SizedBox(height: 28),
                const _FeatureRow(
                    Icons.forum_outlined, 'مُحادثة عامة يراها الجميع'),
                const _FeatureRow(Icons.lock_outline,
                    'مُحادثة خاصة لكل متصل بسرّية'),
                const _FeatureRow(
                    Icons.graphic_eq_rounded, 'رسائل صوتية مسجلة'),
                const _FeatureRow(
                    Icons.insert_drive_file_rounded, 'إرسال واستقبال ملفات'),
                const _FeatureRow(Icons.videocam_outlined, 'مكالمات فيديو مباشرة'),
                const _FeatureRow(
                    Icons.security_rounded, 'تشفير كل الرسائل AES'),
                const SizedBox(height: 30),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.done_rounded),
                  label: const Text('أوه حسناً، فهمت'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _kAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _showPassword = false | true;
  bool _remember = true;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _login() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تسجيل الدخول (واجهة تجريبية)'),
        backgroundColor: _kAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xFF1E3A5F),
                  child: Icon(Icons.person, color: Color(0xFF4FC3F7), size: 34),
                ),
                const SizedBox(height: 16),
                const Text('تسجيل الدخول',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('أدخل بياناتك للوصول إلى حسابك في عميل المحادثة',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                const SizedBox(height: 24),
                TextField(
                  controller: _userController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم:',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور:',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? true),
                    ),
                    const Text('تذكرني', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {},
                      child: const Text('نسيت كلمة المرور؟',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _login,
                    icon: const Icon(Icons.login),
                    label: const Text('دخول'),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('ليس لديك حساب؟',
                        style: TextStyle(color: Colors.grey.shade400)),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const RtlShell(child: RegisterScreen()),
                        ),
                      ),
                      child: const Text('إنشاء حساب'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _userController.dispose();
    _passController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _register() {
    if (_passController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كلمتا المرور غير متطابقتين'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إنشاء الحساب بنجاح'),
        backgroundColor: _kAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('إنشاء حساب جديد'),
        backgroundColor: _kBackground,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xFF1E3A5F),
                  child: Icon(Icons.person_add_alt_1,
                      color: Color(0xFF2ECC71), size: 34),
                ),
                const SizedBox(height: 16),
                const Text('أهلاً بك في عميل المحادثة',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('أنشئ حساباً مجانياً وابدأ المحادثة فوراً',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل:',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم:',
                    prefixIcon: Icon(Icons.alternate_email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور:',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور:',
                    prefixIcon: Icon(Icons.lock_reset),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _register,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('إنشاء الحساب'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _publicChat = true;
  bool _privateChat = true;
  bool _darkMode = true;
  bool _showTimestamps = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('الإعدادات والملف الشخصي'),
        backgroundColor: _kBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFF4FC3F7),
                  child: Text('م',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('مستخدم التطبيق',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.circle, size: 9, color: _kAccent),
                          const SizedBox(width: 6),
                          Text('متصل',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل الصورة',
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('الحساب'),
          _SwitchTile(
            icon: Icons.edit_outlined,
            title: 'تعديل الملف الشخصي',
            value: true,
            onChanged: (_) {},
          ),
          _SwitchTile(
            icon: Icons.password,
            title: 'تغيير كلمة المرور',
            value: true,
            onChanged: (_) {},
          ),
          const SizedBox(height: 18),
          const _SectionTitle('الشات والإشعارات'),
          _SwitchTile(
            icon: Icons.notifications_active_outlined,
            title: 'إشعارات الرسائل الجديدة',
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
          _SwitchTile(
            icon: Icons.campaign_outlined,
            title: 'رسائل صوتية فورية',
            value: _publicChat,
            onChanged: (v) => setState(() => _publicChat = v),
          ),
          _SwitchTile(
            icon: Icons.private_connectivity_outlined,
            title: 'المحادثة الخاصة',
            value: _privateChat,
            onChanged: (v) => setState(() => _privateChat = v),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('المظهر'),
          _SwitchTile(
            icon: Icons.dark_mode_outlined,
            title: 'الوضع الداكن',
            value: _darkMode,
            onChanged: (v) => setState(() => _darkMode = v),
          ),
          _SwitchTile(
            icon: Icons.timer_outlined,
            title: 'عرض الوقت على الرسائل',
            value: _showTimestamps,
            onChanged: (v) => setState(() => _showTimestamps = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ الإعدادات'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF4FC3F7),
              fontWeight: FontWeight.bold,
              fontSize: 14)),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon, color: _kLightBlue),
        title: Text(title, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

class VideoCallDemoScreen extends StatefulWidget {
  const VideoCallDemoScreen({super.key});

  @override
  State<VideoCallDemoScreen> createState() => _VideoCallDemoScreenState();
}

class _VideoCallDemoScreenState extends State<VideoCallDemoScreen> {
  bool _micOn = true;
  bool _camOn = true;
  bool _speakerOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B16),
      appBar: AppBar(
        title: const Text('مكالمة فيديو (تجريبية)'),
        backgroundColor: const Color(0xFF060B16),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D2B4E), Color(0xFF0F172A)],
                  begin: AlignmentDirectional.topCenter,
                  end: AlignmentDirectional.bottomCenter,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 60,
                      backgroundColor: Color(0xFF1E3A5F),
                      child: Icon(Icons.person, size: 64, color: Color(0xFF4FC3F7)),
                    ),
                    const SizedBox(height: 18),
                    const Text('مستخدم المتصل',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('مكالمة فيديو قيد التشغيل...',
                        style: TextStyle(color: Colors.grey.shade400)),
                    const SizedBox(height: 6),
                    Text('00:00:00',
                        style: TextStyle(
                            color: _kLightBlue, fontFeatures: const [])),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              width: 140,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: _camOn
                  ? const Center(
                      child: Icon(Icons.videocam, color: Color(0xFF4FC3F7)))
                  : const Center(
                      child:
                          Icon(Icons.videocam_off, color: Colors.grey)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: const Color(0xCC060B16),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: _micOn ? Icons.mic : Icons.mic_off,
                    active: _micOn,
                    onTap: () => setState(() => _micOn = !_micOn),
                  ),
                  _CallButton(
                    icon: _camOn ? Icons.videocam : Icons.videocam_off,
                    active: _camOn,
                    onTap: () => setState(() => _camOn = !_camOn),
                  ),
                  _CallButton(
                    icon: _speakerOn
                        ? Icons.volume_up
                        : Icons.volume_off,
                    active: _speakerOn,
                    onTap: () => setState(() => _speakerOn = !_speakerOn),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const RtlShell(
                            child: VideoCallEndedScreen()),
                      ),
                    ),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E88E5) : const Color(0xFF263043),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: active ? Colors.white : Colors.grey.shade400),
      ),
    );
  }
}

class VideoCallEndedScreen extends StatelessWidget {
  const VideoCallEndedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B16),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 44,
              backgroundColor: Color(0xFF1E3A5F),
              child: Icon(Icons.call_end, color: Color(0xFF4FC3F7), size: 40),
            ),
            const SizedBox(height: 18),
            const Text('انتهت المكالمة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('استغرق المكالمة: 00:00:42',
                style: TextStyle(color: Colors.grey.shade400)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.replay),
              label: const Text('إعادة الاتصال'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                while (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('العودة إلى الشاشة الرئيسية'),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<String> _items = [
    'وصلتك رسالة خاصة جديدة من [منى]',
    'مستخدم جديد [سامي] انضم إلى الخادم',
    'تم استلام ملف: project_report.pdf',
    'مكالمة فيديو قادمة من [خالد]',
    'تحديث جديد متاح للتطبيق',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('الإشعارات والتحديثات'),
        backgroundColor: _kBackground,
        actions: [
          IconButton(
            tooltip: 'وضع الكل كمقروء',
            icon: const Icon(Icons.done_all),
            onPressed: () {},
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(child: Text('لا توجد إشعارات', style: TextStyle(color: Colors.grey)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kPrimary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFF1E3A5F),
                        child: Icon(Icons.notifications, color: Color(0xFF4FC3F7), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(item, style: const TextStyle(fontSize: 13))),
                      const Icon(Icons.chevron_left, color: Colors.grey),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
