import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api.dart';
import '../main.dart';
import 'home_shell.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';

// Official multi-colour Google "G" logo
const _googleLogoSvg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

class AuthScreen extends StatefulWidget {
  /// Agar main.dart callback deta hai to login ke baad wahi chalega, warna seedha HomeShell khulta hai.
  final VoidCallback? onAuthenticated;
  const AuthScreen({super.key, this.onAuthenticated});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false, _busy = false, _hide = true;

  Future<void> _submit() async {
    if (_register) {
      String? problem;
      if (_name.text.trim().isEmpty) {
        problem = 'Enter your name';
      } else if (!_email.text.contains('@')) {
        problem = 'Enter a valid email';
      } else if (_pass.text != _confirm.text) {
        problem = 'Passwords do not match';
      }
      if (problem != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
        return;
      }
      // second page: email verification (OTP)
      final verified = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => OtpScreen(email: _email.text.trim())));
      if (verified == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (_register) {
        await Api.register(_name.text.trim(), _email.text.trim(), _pass.text);
      } else {
        await Api.login(_email.text.trim(), _pass.text);
      }
      if (!mounted) return;
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Web client ID (client_type 3) from google-services.json
  static const _googleWebClientId = '690646162387-1i02fqiqpfpi30f9rni7tlom0s18c8ra.apps.googleusercontent.com';

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      final gs = GoogleSignIn(scopes: const ['email'], serverClientId: _googleWebClientId);
      await gs.signOut(); // always show the account picker
      final acc = await gs.signIn();
      if (acc == null) return; // user closed the picker
      final idToken = (await acc.authentication).idToken;
      if (idToken == null) throw Exception('Google did not return an ID token');
      await Api.googleLogin(idToken);
      if (!mounted) return;
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _ink = Color(0xFF1A1240); // dark text
  static const _soft = Color(0xFF5A6785); // grey-blue text

  InputDecoration _dec(String label, IconData icon, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: _soft),
        labelStyle: const TextStyle(color: _soft, fontSize: 16),
        floatingLabelStyle: const TextStyle(color: kBlue, fontWeight: FontWeight.w600),
        prefixIcon: Icon(icon, color: kBlue),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: kBlue, width: 1.4)),
      );

  Widget _loginButton() => Container(
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF8B5CF6), Color(0xFF5B2DD0)]),
          boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _busy ? null : _submit,
            child: Stack(alignment: Alignment.center, children: [
              if (_busy)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_register ? Icons.person_add_alt_1_rounded : Icons.login_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(_register ? 'Create account' : 'Login', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              if (!_busy) const Positioned(right: 18, child: Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false, // keyboard must not push the bottom picture up
      body: Stack(fit: StackFit.expand, children: [
        // page background (matches the colour at the bottom of the header picture)
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF6F4FD), kBg]),
            ),
          ),
        ),
        // bottom picture
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Image.asset('assets/images/login_bottom.png', fit: BoxFit.fitWidth, alignment: Alignment.bottomCenter),
        ),
        SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 24 + kb),
          child: Column(children: [
            // header picture: logo + title + tagline + house (goes under the status bar)
            Image.asset('assets/images/login_header.png', width: double.infinity, fit: BoxFit.fitWidth),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(children: [
                  if (_register) ...[
                    TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _dec('Name', Icons.person_outline_rounded)),
                    const SizedBox(height: 14),
                  ],
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _dec('Email', Icons.mail_outline_rounded)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    decoration: _dec('Password', Icons.lock_outline_rounded,
                        hint: 'Enter your password',
                        suffix: IconButton(
                          icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _ink),
                          onPressed: () => setState(() => _hide = !_hide),
                        )),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 14),
                    TextField(controller: _confirm, obscureText: _hide, decoration: _dec('Confirm password', Icons.lock_reset_rounded)),
                  ],
                  if (!_register)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim()))),
                        child: const Text('Forgot password?', style: TextStyle(color: kBlue, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  SizedBox(height: _register ? 18 : 2),
                  _loginButton(),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: _register ? 'Already have an account? ' : 'New here? ', style: const TextStyle(color: Color(0xFF5B3FD0), fontWeight: FontWeight.w500)),
                      TextSpan(text: _register ? 'Login' : 'Sign up', style: const TextStyle(color: kBlue, fontWeight: FontWeight.w800)),
                    ]), style: const TextStyle(fontSize: 16)),
                  ),
                  if (Api.remote) ...[
                    const Row(children: [
                      Expanded(child: Divider(color: Color(0xFFD9D4EE))),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('or', style: TextStyle(color: _soft, fontSize: 15))),
                      Expanded(child: Divider(color: Color(0xFFD9D4EE))),
                    ]),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _ink,
                          side: const BorderSide(color: Color(0xFFB9A4F5), width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: _busy ? null : _google,
                        icon: SvgPicture.string(_googleLogoSvg, width: 26, height: 26),
                        label: const Text('Continue with Google', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 120), // space so the card can scroll above the bottom picture
          ]),
        ),
      ]),
    );
  }
}