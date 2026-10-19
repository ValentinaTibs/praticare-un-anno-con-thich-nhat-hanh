import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../auth/auth_notifier.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/confirmation_request.dart';

final _confirmationProvider = FutureProvider<ConfirmationRequest?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/api/confirmations/pending');
  if (data == null) return null;
  return ConfirmationRequest.fromJson(data as Map<String, dynamic>);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final confirmAsync = ref.watch(_confirmationProvider);

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/auth/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  child: Text(
                    user.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 12),
                Text('${user.name} ${user.surname}', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                _StatusChip(status: user.status),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (user.email != null)
            _InfoRow(label: 'Email', value: user.email!),
          _InfoRow(label: 'Role', value: user.role),
          if (user.lastConfirmedAt != null)
            _InfoRow(
              label: 'Last confirmed',
              value: DateFormat('d MMM yyyy').format(user.lastConfirmedAt!.toLocal()),
            ),
          const SizedBox(height: 24),
          confirmAsync.when(
            data: (req) => req != null ? _ConfirmationBanner(req: req) : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('Active', Colors.green),
      'suspended' => ('Suspended', Colors.orange),
      'banned' => ('Banned', Colors.red),
      _ => (status, Colors.grey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ConfirmationBanner extends ConsumerWidget {
  final ConfirmationRequest req;
  const _ConfirmationBanner({required this.req});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text('Confirmation required', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.error)),
            ]),
            const SizedBox(height: 8),
            Text('Please confirm your participation by ${DateFormat('d MMM yyyy').format(req.dueAt.toLocal())} to keep your account active.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await ref.read(authProvider.notifier).confirm();
                ref.invalidate(_confirmationProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Participation confirmed!')));
                }
              },
              child: const Text('Confirm my participation'),
            ),
          ],
        ),
      ),
    );
  }
}
