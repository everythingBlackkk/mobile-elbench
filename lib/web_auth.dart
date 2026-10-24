import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'main.dart';
import 'screens.dart' show AuthHeader, NativePage;
import 'web_style.dart';

/// The mobile auth/signup.blade.php flow, rendered using native controls.
class WebSignupPage extends StatefulWidget {
  const WebSignupPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<WebSignupPage> createState() => _WebSignupPageState();
}

class _WebSignupPageState extends State<WebSignupPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late final TapGestureRecognizer _termsTap;
  int _step = 1;
  bool _loading = true, _busy = false, _terms = false;
  String? _error, _message, _verifiedName, _verifiedMajor;
  DateTime? _resendAt;
  Timer? _ticker;
  AppController get c => widget.controller;
  int get _wait {
    final millis = _resendAt?.difference(DateTime.now()).inMilliseconds ?? 0;
    return millis <= 0 ? 0 : (millis / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = _openTerms;
    final persisted = c.settings.preferences?.getInt(
      'signup.resend_available_at',
    );
    if (persisted != null) {
      _resendAt = DateTime.fromMillisecondsSinceEpoch(persisted);
    }
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _step == 2 && !_loading) setState(() {});
    });
  }

  Future<void> _load() async {
    try {
      final data = object((await c.get('/signup'))['data']);
      _step = (int.tryParse(value(data['step'])) ?? 1).clamp(1, 3);
      _email.text = value(data['pendingEmail']);
      _verifiedName = data['verifiedName'] as String?;
      _verifiedMajor = data['verifiedMajor'] as String?;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _cooldown(Json response) {
    final seconds = int.tryParse(value(response['cooldown_seconds'])) ?? 60;
    _resendAt = DateTime.now().add(Duration(seconds: seconds));
    c.settings.preferences?.setInt(
      'signup.resend_available_at',
      _resendAt!.millisecondsSinceEpoch,
    );
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      if (_step == 1) {
        final response = await c.action('POST', '/signup/otp', {
          'email': _email.text.trim(),
        });
        _cooldown(response);
        if (mounted) {
          setState(() {
            _step = 2;
            _code.clear();
            _message = response['message'] as String?;
          });
        }
      } else if (_step == 2) {
        final response = await c.action('POST', '/signup/verify', {
          'otp_code': _code.text.trim(),
        });
        final verified = object(response['data']);
        final page = object((await c.get('/signup'))['data']);
        c.settings.preferences?.remove('signup.resend_available_at');
        if (mounted) {
          setState(() {
            _step = 3;
            _verifiedName = value(page['verifiedName'] ?? verified['name']);
            _verifiedMajor = value(page['verifiedMajor'] ?? verified['major']);
            _terms = false;
          });
        }
      } else {
        await c.action('POST', '/signup', {
          'password': _password.text,
          'password_confirmation': _confirmation.text,
          'terms': _terms,
        });
        try {
          await c.get('/mobile/session');
          if (c.enablePush) await c.push.bind(c.user, c.settings.language);
        } catch (_) {}
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || _wait > 0) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await c.action('POST', '/signup/otp', {
        'email': _email.text.trim(),
      });
      _cooldown(response);
      if (mounted) setState(() => _message = response['message'] as String?);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openTerms() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NativePage(controller: c, path: '/terms'),
    ),
  );

  @override
  void dispose() {
    _ticker?.cancel();
    _termsTap.dispose();
    for (final input in [_email, _code, _password, _confirmation]) {
      input.dispose();
    }
    super.dispose();
  }

  Widget _label(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  Widget _primary(String title, {bool arrow = false}) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(13),
      boxShadow: const [
        BoxShadow(color: Color(0xff18251a), offset: Offset(0, 4)),
      ],
    ),
    child: FilledButton(
      key: const ValueKey('signup.submit'),
      onPressed: _busy ? null : _submit,
      style:
          FilledButton.styleFrom(
            backgroundColor: const Color(0xff428735),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xff356e2a),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.92),
            minimumSize: const Size(double.infinity, 49),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: const BorderSide(color: Color(0xff18251a), width: 1.5),
            ),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return const Color(0xff2c5d23).withValues(alpha: 0.35);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return Colors.white.withValues(alpha: 0.08);
              }
              return null;
            }),
          ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              _busy ? c.t('Please wait…', 'استنى لحظة…') : title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (arrow) ...[
            const SizedBox(width: 10),
            WebIcon(
              c.settings.language == 'ar' ? 'back' : 'chevron-right',
              size: 16,
              color: Colors.white,
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c.settings,
    builder: (context, _) {
      final theme = Theme.of(context),
          scheme = theme.colorScheme,
          muted = theme.colorScheme.onSurfaceVariant;
      final required = c.t('This field is required', 'هذا الحقل مطلوب');
      return Scaffold(
        body: SafeArea(
          child: ListView(
            children: [
              AuthHeader(controller: c),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        c.t('Create an account', 'إنشاء حساب'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 28,
                          height: 1.4,
                          letterSpacing: c.settings.language == 'en' ? -.7 : 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.t(
                          'Your campus community is waiting.',
                          'مجتمع جامعتك مستنيك.',
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.8,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          for (int n = 1; n <= 3; n++)
                            Expanded(
                              child: Container(
                                height: 4,
                                margin: EdgeInsetsDirectional.only(
                                  end: n == 3 ? 0 : 7,
                                ),
                                decoration: BoxDecoration(
                                  color: _step >= n
                                      ? c.settings.accent
                                      : scheme.outlineVariant,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else ...[
                        if (_error != null || _message != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.symmetric(
                              vertical: 13,
                              horizontal: 15,
                            ),
                            decoration: BoxDecoration(
                              color: _error != null
                                  ? scheme.error.withValues(alpha: .08)
                                  : scheme.primaryContainer,
                              border: Border.all(
                                color: _error != null
                                    ? scheme.error.withValues(alpha: .25)
                                    : scheme.primary.withValues(alpha: .25),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error ?? _message!,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.7,
                                color: _error != null
                                    ? scheme.error
                                    : scheme.primary,
                              ),
                            ),
                          ),
                        if (_step == 1) ...[
                          _label(c.t('University email', 'الإيميل الجامعي')),
                          TextFormField(
                            key: const ValueKey('signup.email'),
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              hintText: 'example@fa-hists.edu.eg',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? required
                                : !v.contains('@')
                                ? c.t(
                                    'Enter a valid email address',
                                    'أدخل بريدًا إلكترونيًا صحيحًا',
                                  )
                                : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 28),
                          _primary(
                            c.t('Send verification code', 'ابعت كود التأكيد'),
                            arrow: true,
                          ),
                        ] else if (_step == 2) ...[
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      '${c.t('Code sent to', 'الكود اتبعت لـ')} ',
                                  style: TextStyle(color: muted),
                                ),
                                TextSpan(
                                  text: _email.text,
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _label(c.t('Verification code', 'كود التأكيد')),
                          TextFormField(
                            key: const ValueKey('signup.code'),
                            controller: _code,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                            decoration: const InputDecoration(
                              hintText: '000000',
                            ),
                            validator: (v) => v == null || v.length != 6
                                ? c.t(
                                    'Enter the six-digit verification code.',
                                    'أدخل رمز التحقق المكوّن من ستة أرقام.',
                                  )
                                : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 28),
                          _primary(c.t('Verify code', 'تأكيد الكود')),
                          const SizedBox(height: 12),
                          TextButton(
                            key: const ValueKey('signup.resend'),
                            onPressed: _busy || _wait > 0 ? null : _resend,
                            child: Text(
                              _wait > 0
                                  ? c.t(
                                      'Resend code ($_wait seconds)',
                                      'إرسال الكود تاني ($_wait ثانية)',
                                    )
                                  : c.t('Resend code', 'إرسال الكود تاني'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ] else ...[
                          if (_verifiedName != null &&
                              _verifiedName!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 22),
                              decoration: BoxDecoration(
                                color: theme.scaffoldBackgroundColor,
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.t('Verified details', 'البيانات الموثقة'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _verifiedName!,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (_verifiedMajor?.isNotEmpty ?? false)
                                    Text(
                                      _verifiedMajor!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          _label(c.t('Choose a password', 'اختار كلمة سر')),
                          TextFormField(
                            key: const ValueKey('signup.password'),
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              hintText: '••••••••',
                            ),
                            validator: (v) => v == null || v.length < 8
                                ? c.t(
                                    'Use at least 8 characters.',
                                    'استخدم ٨ أحرف على الأقل.',
                                  )
                                : null,
                          ),
                          const SizedBox(height: 20),
                          _label(c.t('Confirm password', 'تأكيد كلمة السر')),
                          TextFormField(
                            key: const ValueKey('signup.passwordConfirmation'),
                            controller: _confirmation,
                            enabled: !_busy,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              hintText: '••••••••',
                            ),
                            validator: (v) => v != _password.text
                                ? c.t(
                                    'The passwords do not match.',
                                    'كلمتا السر غير متطابقتين.',
                                  )
                                : null,
                          ),
                          const SizedBox(height: 18),
                          FormField<bool>(
                            key: const ValueKey('signup.terms'),
                            initialValue: _terms,
                            validator: (_) => !_terms
                                ? c.t(
                                    'Accept the terms to create your account.',
                                    'وافق على الشروط لإنشاء حسابك.',
                                  )
                                : null,
                            builder: (state) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 17,
                                      height: 25,
                                      child: Checkbox(
                                        value: _terms,
                                        activeColor: const Color(0xff428735),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: _busy
                                            ? null
                                            : (v) {
                                                setState(
                                                  () => _terms = v ?? false,
                                                );
                                                state.didChange(_terms);
                                              },
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text:
                                                  '${c.t('I have read and agree to the', 'أنا قرأت وموافق على')} ',
                                            ),
                                            TextSpan(
                                              text: c.t(
                                                'terms and conditions',
                                                'الشروط والأحكام',
                                              ),
                                              recognizer: _termsTap,
                                              style: TextStyle(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w700,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  ' ${c.t('and ElBench’s usage policy.', 'وسياسة الاستخدام بتاعة ElBench.')}',
                                            ),
                                          ],
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.6,
                                          fontWeight: FontWeight.w500,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (state.errorText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      state.errorText!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.error,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          _primary(c.t('Create an account', 'إنشاء حساب')),
                        ],
                      ],
                      const SizedBox(height: 28),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          Text(
                            c.t(
                              'Already have an account?',
                              'عندك حساب بالفعل؟',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.8,
                              color: muted,
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: Text(
                              c.t('Log in', 'سجل دخول'),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.8,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
