import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_client.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

class PushService {
  final ApiClient _api;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  PushService(this._api);

  Future<void> init() async {
    if (kIsWeb) return; // push notifications not supported on web

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails('default', 'Default', importance: Importance.high),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });

    await _registerToken();
  }

  Future<void> _registerToken() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _api.post('/api/auth/devices', data: {'fcmToken': token});
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _api.post('/api/auth/devices', data: {'fcmToken': newToken});
    });
  }

  Future<void> unregisterToken() async {
    if (kIsWeb) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _api.delete('/api/auth/devices', data: {'fcmToken': token});
    }
  }
}
