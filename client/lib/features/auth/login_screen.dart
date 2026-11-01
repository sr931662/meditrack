import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/storage/server_url_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import 'auth_controller.dart';

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'MediTrack',
        child: ExcludeSemantics(
          child: RichText(
            text: TextSpan(style: TextStyle(fontFamily: 'Figtree', fontSize: size, fontWeight: FontWeight.w800, letterSpacing: .3, color: Mt.ink), children: const [
              TextSpan(text: 'MEDI'),
              TextSpan(text: 'TRACK', style: TextStyle(color: Mt.blue)),
            ]),
          ),
        ),
      );
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.registerMode = false});
  final bool registerMode;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late bool _register = widget.registerMode;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _server() async {
    final ctl = TextEditingController(text: ref.read(apiBaseUrlProvider));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Server address'),
        content: TextField(controller: ctl, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://your-service.run.app')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
      ),
    );
    if (ok != true) return;
    final url = ServerUrlStore.normalize(ctl.text);
    if (url == null) {
      setState(() => _error = 'That does not look like a web address.');
      return;
    }
    await ServerUrlStore.write(url);
    ref.read(apiBaseUrlProvider.notifier).set(url);
    if (mounted) setState(() => _error = null);
  }

  Future<void> _demo(String email) async {
    _email.text = email;
    _password.text = 'Demo@12345';
    _register = false;
    await _submit();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty || (_register && _name.text.trim().isEmpty)) {
      setState(() => _error = _register ? 'Enter your name, email and a password.' : 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      _register ? await auth.register(_email.text, _password.text, _name.text) : await auth.login(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final notice = state is Unauthenticated ? state.message : null;
    return Scaffold(
      body: PageBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Center(child: Wordmark(size: 34)),
                    const SizedBox(height: 8),
                    const Text('Medication reminders that look out for you.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Mt.muted)),
                    const SizedBox(height: 28),
                    MtCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Semantics(header: true, child: Text(_register ? 'Create your account' : 'Sign in', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                        if (notice != null) ...[const SizedBox(height: 10), Text(notice, style: const TextStyle(color: Mt.warn, fontSize: 15))],
                        const SizedBox(height: 16),
                        if (_register) ...[LabeledField(label: 'Your name', controller: _name, autofillHints: const [AutofillHints.name]), const SizedBox(height: 14)],
                        LabeledField(label: 'Email', controller: _email, keyboard: TextInputType.emailAddress, autofillHints: const [AutofillHints.email]),
                        const SizedBox(height: 14),
                        LabeledField(label: 'Password', controller: _password, obscure: true, hint: _register ? 'At least 10 characters, letters and numbers' : null, autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password]),
                        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: Mt.dangerDeep, fontSize: 15)))),
                        const SizedBox(height: 18),
                        PrimaryButton(_register ? 'Create account' : 'Sign in', onPressed: _submit, loading: _busy),
                        const SizedBox(height: 6),
                        TextAction(_register ? 'I already have an account' : 'Create a caregiver account', onPressed: () => setState(() {
                              _register = !_register;
                              _error = null;
                            })),
                      ]),
                    ),
                    if (Env.demoLogins) ...[
                      const SizedBox(height: 16),
                      MtCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Text('Demo accounts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          const Text('Sample data. Alerts are simulated; nothing is sent to a real phone.', style: TextStyle(fontSize: 13, color: Mt.muted)),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton(onPressed: _busy ? null : () => _demo('senior@demo.meditrack.app'), child: const Text('Senior (Kamla)')),
                            OutlinedButton(onPressed: _busy ? null : () => _demo('caregiver@demo.meditrack.app'), child: const Text('Caregiver (Priya)')),
                            OutlinedButton(onPressed: _busy ? null : () => _demo('admin@demo.meditrack.app'), child: const Text('Admin')),
                          ]),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextAction('Server: ${Uri.tryParse(ref.watch(apiBaseUrlProvider))?.host ?? ''}', onPressed: _server),
                    const Text('Seniors sign in with the email and password their caregiver set up.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Mt.muted)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
