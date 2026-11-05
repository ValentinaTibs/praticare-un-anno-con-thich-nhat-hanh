import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_errors.dart';
import '../panel_config.dart';
import 'panel_auth_notifier.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtr = TextEditingController();
  final _passwordCtr = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtr.dispose();
    _passwordCtr.dispose();
    super.dispose();
  }

  /// Runs a login step, showing its error under the form. On success the
  /// router redirect leaves this page.
  Future<void> _run(Future<void> Function(PanelAuthNotifier auth) step) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await step(ref.read(panelAuthProvider.notifier));
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _run((auth) => auth.signIn(_emailCtr.text.trim(), _passwordCtr.text));
  }

  void _devLogin() {
    final email = _emailCtr.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Inserisci l\'email dell\'utente di prova.');
      return;
    }
    _run((auth) => auth.devLogin(email));
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtr.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Inserisci la tua email per reimpostare la password.');
      return;
    }
    await _run((auth) => auth.sendPasswordReset(email));
    if (mounted && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ti abbiamo inviato un\'email a $email per reimpostare la password.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error ?? ref.watch(panelAuthProvider).message;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Pannello di amministrazione', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Accesso riservato ad admin e Super Admin, con l\'email e la password che usi nell\'app.',
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailCtr,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtr,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Mostra la password' : 'Nascondi la password',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Campo obbligatorio' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        child: const Text('Password dimenticata?'),
                      ),
                    ),
                    if (error != null) ...[
                      Text(error, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Accedi'),
                    ),
                    if (PanelConfig.devLogin) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loading ? null : _devLogin,
                        child: const Text('Accesso di sviluppo (senza password)'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
