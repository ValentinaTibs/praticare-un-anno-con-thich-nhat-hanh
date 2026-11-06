import 'package:community_app/core/models/main_channel_post.dart';
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
}

class FakePush extends Fake implements PushService {
  Future<void> Function()? onInit;
  Future<void> Function()? onUnregister;

  @override
  Future<void> init() async => onInit?.call();

  @override
  Future<void> unregisterToken() async => onUnregister?.call();
}
