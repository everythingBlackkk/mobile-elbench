import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart';
import 'text_direction.dart';

/// The menu's centered password dialog, using the published menu form contract.
Future<void> showWebSecurity(BuildContext context, NativePageState page) async {
  final result = await showGeneralDialog<Json>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => _WebSecurityDialog(page: page),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
  if (result == null || !page.mounted) return;
  if (result['reset'] == true) {
    page.c.open('/profile/password/reset');
  } else {
    await page.load(value(result['redirect_url'], '/profile'));
  }
}

class _WebSecurityDialog extends StatefulWidget {
  const _WebSecurityDialog({required this.page});
  final NativePageState page;
  @override
  State<_WebSecurityDialog> createState() => _WebSecurityDialogState();
}

class _WebSecurityDialogState extends State<_WebSecurityDialog> {
  final current = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    current.clear();
    password.clear();
    confirmation.clear();
    current.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    final c = widget.page.c;
    String? invalid;
    if (current.text.isEmpty) {
      invalid = c.t('Enter your current password.', 'اكتب كلمة السر الحالية.');
    }
    if (password.text.length < 6 || password.text.length > 72) {
      invalid ??= c.t(
        'The password must contain between 6 and 72 characters.',
        'كلمة السر لازم تكون من ٦ إلى ٧٢ حرف.',
      );
    }
    if (password.text != confirmation.text) {
      invalid ??= c.t(
        'The password confirmation does not match.',
        'تأكيد كلمة السر مش مطابق.',
      );
    }
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await c.action('POST', '/menu', {
        'old_password': current.text,
        'new_password': password.text,
        'confirm_password': confirmation.text,
        'change_password': '',
      });
      current.clear();
      password.clear();
      confirmation.clear();
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.page.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xff141414) : const Color(0xfff9fafb);
    final main = dark ? const Color(0xff0a0a0a) : Colors.white;
    final foreground = dark ? const Color(0xfff3f4f6) : const Color(0xff111827);
    final muted = dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
    final border = dark ? const Color(0xff303030) : const Color(0xffe5e7eb);
    final accent = dark ? const Color(0xff7ace9f) : const Color(0xff2e855d);
    final danger = dark ? const Color(0xffe7767d) : const Color(0xffc53d46);
    final media = MediaQuery.of(context);

    Widget field(
      String label,
      TextEditingController controller, {
      required bool old,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: foreground,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 46,
          child: AdaptiveTextField(
            controller: controller,
            field: (direction) => TextField(
              controller: controller,
              textDirection: direction,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: old
                  ? const [AutofillHints.password]
                  : const [AutofillHints.newPassword],
              maxLength: old ? null : 72,
              textInputAction: controller == confirmation
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted: controller == confirmation ? (_) => submit() : null,
              style: TextStyle(fontSize: 16, color: foreground),
              decoration: InputDecoration(
                filled: true,
                fillColor: main,
                counterText: '',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: border),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: const ColoredBox(color: Color(0x80000000)),
          ),
        ),
        AnimatedPadding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + media.viewInsets.bottom,
          ),
          duration: const Duration(milliseconds: 150),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: math.max(
                  0,
                  math.min(
                    media.size.height * .9,
                    media.size.height - 48 - media.viewInsets.bottom,
                  ),
                ),
              ),
              child: Material(
                color: background,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        offset: Offset(0, 16),
                        blurRadius: 48,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.t('Change Password', 'تغيير الباسوورد'),
                                style: TextStyle(
                                  fontSize: 20,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                  color: foreground,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => Navigator.pop(context),
                              customBorder: const CircleBorder(),
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(
                                  Icons.close,
                                  size: 17,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (error != null) ...[
                          Text(
                            error!,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: danger,
                            ),
                          ),
                          const SizedBox(height: 15),
                        ],
                        field(
                          c.t('Current password', 'كلمة السر الحالية'),
                          current,
                          old: true,
                        ),
                        const SizedBox(height: 15),
                        field(
                          c.t('New password', 'كلمة السر الجديدة'),
                          password,
                          old: false,
                        ),
                        const SizedBox(height: 15),
                        field(
                          c.t(
                            'Confirm new password',
                            'تأكيد كلمة السر الجديدة',
                          ),
                          confirmation,
                          old: false,
                        ),
                        const SizedBox(height: 20),
                        Material(
                          color: const Color(0xff2e855d),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: busy ? null : submit,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                busy
                                    ? '…'
                                    : c.t('Change password', 'تغيير كلمة السر'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: InkWell(
                            onTap: () =>
                                Navigator.pop(context, {'reset': true}),
                            child: Text(
                              c.t(
                                'Forgot your password? Reset it',
                                'نسيت كلمة السر؟ غيّرها',
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
