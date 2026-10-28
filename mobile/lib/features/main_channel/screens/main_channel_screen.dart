import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main_channel_notifier.dart';
import '../../../core/models/main_channel_post.dart';

class MainChannelScreen extends ConsumerWidget {
  const MainChannelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mainChannelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(mainChannelProvider.notifier).load(refresh: true),
        child: state.loading && state.posts.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.posts.isEmpty
                ? Center(child: Text(state.error!))
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 && state.hasMore) {
                        ref.read(mainChannelProvider.notifier).load();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: state.posts.length + (state.hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == state.posts.length) {
                          return const Center(child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ));
                        }
                        return _PostCard(post: state.posts[i]);
                      },
                    ),
                  ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final MainChannelPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    final date = post.publishedAt ?? post.createdAt;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(author != null ? author.name[0].toUpperCase() : '?'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author != null ? author.fullName : 'Utente eliminato',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        DateFormat('d MMM yyyy, HH:mm').format(date.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(post.content),
          ],
        ),
      ),
    );
  }
}
