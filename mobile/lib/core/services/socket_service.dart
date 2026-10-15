import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../constants.dart';
import '../models/main_channel_post.dart';
import '../models/sharing_channel_post.dart';

class SharingChannelStatus {
  final String channelId;
  final DateTime? scheduledClosedAt;
  final int? minutesRemaining;

  SharingChannelStatus({required this.channelId, this.scheduledClosedAt, this.minutesRemaining});
}

class SocketService {
  sio.Socket? _socket;

  final _newMainPost = StreamController<MainChannelPost>.broadcast();
  final _sharingOpened = StreamController<SharingChannelStatus>.broadcast();
  final _sharingClosed = StreamController<String>.broadcast();
  final _sharingNewPost = StreamController<SharingChannelPost>.broadcast();
  final _sharingPostDeleted = StreamController<String>.broadcast();
  final _sharingClosingSoon = StreamController<SharingChannelStatus>.broadcast();

  Stream<MainChannelPost> get onNewMainPost => _newMainPost.stream;
  Stream<SharingChannelStatus> get onSharingOpened => _sharingOpened.stream;
  Stream<String> get onSharingClosed => _sharingClosed.stream;
  Stream<SharingChannelPost> get onSharingNewPost => _sharingNewPost.stream;
  Stream<String> get onSharingPostDeleted => _sharingPostDeleted.stream;
  Stream<SharingChannelStatus> get onSharingClosingSoon => _sharingClosingSoon.stream;

  void connect(String accessToken) {
    _socket = sio.io(
      AppConstants.socketUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {});
    _socket!.onDisconnect((_) {});

    _socket!.on('main_channel:new_post', (data) {
      _newMainPost.add(MainChannelPost.fromJson(Map<String, dynamic>.from(data as Map)));
    });

    _socket!.on('sharing_channel:opened', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _sharingOpened.add(SharingChannelStatus(
        channelId: d['channelId'] as String,
        scheduledClosedAt: d['scheduledClosedAt'] != null
            ? DateTime.parse(d['scheduledClosedAt'] as String)
            : null,
      ));
    });

    _socket!.on('sharing_channel:closed', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _sharingClosed.add(d['channelId'] as String);
    });

    _socket!.on('sharing_channel:new_post', (data) {
      _sharingNewPost.add(SharingChannelPost.fromJson(Map<String, dynamic>.from(data as Map)));
    });

    _socket!.on('sharing_channel:post_deleted', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _sharingPostDeleted.add(d['id'] as String);
    });

    _socket!.on('sharing_channel:closing_soon', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _sharingClosingSoon.add(SharingChannelStatus(
        channelId: d['channelId'] as String,
        scheduledClosedAt: DateTime.parse(d['scheduledClosedAt'] as String),
        minutesRemaining: d['minutesRemaining'] as int?,
      ));
    });

    _socket!.connect();
  }

  void subscribeToSharingChannel(String channelId) {
    _socket?.emit('sharing_channel:subscribe', {'channelId': channelId});
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _newMainPost.close();
    _sharingOpened.close();
    _sharingClosed.close();
    _sharingNewPost.close();
    _sharingPostDeleted.close();
    _sharingClosingSoon.close();
  }
}
