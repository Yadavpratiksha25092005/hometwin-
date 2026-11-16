import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api.dart';
import '../main.dart';
import 'home_shell.dart';

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
  bool _register = false, _busy = false, _hide = true;

  Future<void> _submit() async {
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

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBlue, width: 1.6)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0xFFFFF1D0), kBg]),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 8))],
                    ),
                    child: const Icon(Icons.home_work_rounded, size: 48, color: kBlue),
                  ),
                  const SizedBox(height: 16),
                  const Text('Home Digital Twin', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kNavy)),
                  const SizedBox(height: 4),
                  const Text('Your Home. Digitized. Organized. Protected.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF5A6785))),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _dec('Name', Icons.person_outline)),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _dec('Email', Icons.mail_outline)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    decoration: _dec('Password', Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        )),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(_register ? 'Create account' : 'Login', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'Already have an account? Login' : 'New here? Sign up'),
                  ),
                  if (Api.remote) ...[
                    const SizedBox(height: 4),
                    const Row(children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Color(0xFF5A6785)))),
                      Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF3C4043),
                          side: const BorderSide(color: kBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _busy ? null : _google,
                        icon: SvgPicture.string(_googleLogoSvg, width: 22, height: 22),
                        label: const Text('Continue with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}