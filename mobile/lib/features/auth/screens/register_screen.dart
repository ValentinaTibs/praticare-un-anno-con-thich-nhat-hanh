import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth_notifier.dart';

/// Shown when the verified Firebase email is not yet known to the backend.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _surnameCtr = TextEditingController();
  final _motivationCtr = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtr.dispose();
    _surnameCtr.dispose();
    _motivationCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final step = await ref.read(authProvider.notifier).register(
            name: _nameCtr.text.trim(),
            surname: _surnameCtr.text.trim(),
            motivation: _motivationCtr.text.trim(),
          );
      if (mounted && step == AuthStep.verifyEmail) context.go('/auth/verify-email');
      // On AuthStep.loggedIn the router redirect takes the user to /home.
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exit() async {
    await ref.read(authProvider.notifier).signOutFirebase();
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.read(authProvider.notifier).firebaseEmail;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa la registrazione'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: _loading ? null : _exit, child: const Text('Esci')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parlaci di te', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Gli amministratori leggeranno la tua motivazione.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                if (email != null) ...[
                  const SizedBox(height: 8),
                  Text('Account: $email', style: TextStyle(color: Colors.grey[600])),
                ],
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameCtr,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _surnameCtr,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Cognome', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _motivationCtr,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Perché vuoi entrare nella comunità?',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Entra'),
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
