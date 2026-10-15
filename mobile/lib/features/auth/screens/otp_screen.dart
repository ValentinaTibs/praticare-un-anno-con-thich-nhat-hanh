import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth_notifier.dart';
import '../../../core/api/api_client.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.length != 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final status = await ref.read(authProvider.notifier).verifyOtp(widget.phoneNumber, code);
      if (!mounted) return;
      if (status == 'register') {
        context.pushReplacement('/auth/register', extra: {'phone': widget.phoneNumber, 'code': code});
      }
      // If status == 'ok' the router redirect handles navigation to /home
    } on ApiException catch (e) {
      setState(() => _error = e.contact != null ? '${e.message}\nContact: ${e.contact}' : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() { _error = null; _ctrl.clear(); });
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phoneNumber);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code resent')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('Enter the code sent to', style: Theme.of(context).textTheme.titleMedium),
              Text(widget.phoneNumber, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
                decoration: InputDecoration(
                  counterText: '',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                  hintText: '000000',
                ),
                onChanged: (v) { if (v.length == 6) _submit(); },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Verify'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _resend,
                  child: const Text("Didn't receive a code? Resend"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
