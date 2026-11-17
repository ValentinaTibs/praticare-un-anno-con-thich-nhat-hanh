import 'package:community_app/core/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePush extends Fake implements PushService {
  Future<void> Function()? onInit;
  Future<void> Function()? onUnregister;

  @override
  Future<void> init() async => onInit?.call();

  @override
  Future<void> unregisterToken() async => onUnregister?.call();
}
