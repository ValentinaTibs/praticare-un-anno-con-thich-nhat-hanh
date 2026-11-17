import 'package:community_app/core/models/main_channel_post.dart';
import 'package:community_app/core/models/sharing_channel_post.dart';
import 'package:community_app/core/services/push_service.dart';
import 'package:community_app/core/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSocket extends Fake implements SocketService {
  final List<String> connected = [];
  int disconnected = 0;

  @override
  void connect(String accessToken) => connected.add(accessToken);

  @override
  void disconnect() => disconnected++;

  @override
  Stream<MainChannelPost> get onNewMainPost => const Stream.empty();

  // The backend sends nothing over the socket: the circle never hears from it.
  @override
  Stream<SharingChannelStatus> get onSharingOpened => const Stream.empty();

  @override
  Stream<String> get onSharingClosed => const Stream.empty();

  @override
  Stream<SharingChannelPost> get onSharingNewPost => const Stream.empty();

  @override
  Stream<String> get onSharingPostDeleted => const Stream.empty();

  @override
  Stream<SharingChannelStatus> get onSharingClosingSoon => const Stream.empty();

  @override
  void subscribeToSharingChannel(String channelId) {}
}

class FakePush extends Fake implements PushService {
  Future<void> Function()? onInit;
  Future<void> Function()? onUnregister;

  @override
  Future<void> init() async => onInit?.call();

  @override
  Future<void> unregisterToken() async => onUnregister?.call();
}
