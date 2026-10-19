import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth_notifier.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final step = await ref.read(authProvider.notifier).continueAfterVerification();
      if (!mounted) return;
      switch (step) {
        case AuthStep.verifyEmail:
          setState(() => _error =
              'L\'email non risulta ancora confermata. Apri il link di conferma (controlla anche lo spam) '
              'oppure tocca "Invia di nuovo".');
        case AuthStep.register:
          context.go('/auth/register');
        case AuthStep.loggedIn:
          break; // the router redirect takes the user to /home
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await ref.read(authProvider.notifier).resendVerificationEmail();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Email di conferma inviata di nuovo.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
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
        title: const Text('Conferma la tua email'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.mark_email_unread_outlined, size: 56),
              const SizedBox(height: 24),
              Text('Devi confermare l\'indirizzo', style: Theme.of(context).textTheme.titleMedium),
              if (email != null)
                Text(email, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(
                'Apri l\'email di conferma e tocca il link, poi torna qui. '
                'Se non l\'hai ricevuta o il link è scaduto, tocca "Invia di nuovo".',
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _continue,
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Ho confermato'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loading ? null : _resend,
                  child: const Text('Invia di nuovo'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _exit,
                  child: const Text('Esci'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
