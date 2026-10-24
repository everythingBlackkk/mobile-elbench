import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

const _channel = AndroidNotificationChannel(
  'elbench_updates',
  'ElBench activity',
  description: 'Replies, likes, announcements and inbox messages',
  importance: Importance.high,
);
const _storage = FlutterSecureStorage();

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (!Platform.isAndroid || message.notification != null) return;
  final recipient = await _storage.read(key: 'elbench.push.recipient');
  if (recipient == null || value(message.data['recipient']) != recipient) {
    return;
  }
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
    ),
  );
  await notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);
  await notifications.show(
    message.messageId.hashCode & 0x7fffffff,
    value(message.data['title'], 'ElBench'),
    value(message.data['body']),
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

class PushService extends ChangeNotifier {
  PushService(this.api, this.navigate);
  final MobileApi api;
  final void Function(String) navigate;
  String state = 'Notifications have not been enabled on this device.';
  bool available = false, enabled = false, registered = false;
  String? _token, _user, _locale, _persistedRecipient;
  final _notifications = FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (Platform.isIOS &&
        !const bool.fromEnvironment('IOS_PUSH_ENABLED', defaultValue: false)) {
      state = 'Push notifications are not configured for this iOS build yet.';
      notifyListeners();
      return;
    }
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          try {
            _open(object(jsonDecode(response.payload ?? '{}')));
          } catch (_) {}
        },
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: true,
            sound: false,
          );
      _subscriptions.add(FirebaseMessaging.onMessage.listen(_foreground));
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data)),
      );
      _subscriptions.add(
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
          _token = token;
          if (_user != null && enabled) await _register();
        }),
      );
      available = true;
      final status = await FirebaseMessaging.instance.getNotificationSettings();
      enabled =
          status.authorizationStatus == AuthorizationStatus.authorized ||
          status.authorizationStatus == AuthorizationStatus.provisional;
      state = enabled
          ? 'Notifications are enabled.'
          : 'Tap Enable to allow notifications.';
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pending = initial.data;
      // A tapped local (foreground or Android background) notification that
      // launched the app is only reported here, not by Firebase.
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (_pending == null &&
          launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse?.payload != null) {
        try {
          _pending = object(jsonDecode(launch!.notificationResponse!.payload!));
        } catch (_) {}
      }
    } catch (_) {
      state = 'Push notifications are not configured for this build yet.';
    }
    notifyListeners();
  }

  Json? _pending;
  Future<void> bind(Json? user, String locale) async {
    final id = user == null ? null : value(user['id']);
    final changed = id != _user || locale != _locale;
    _user = id;
    _locale = locale;
    if (id == null) {
      if (_persistedRecipient != null) {
        _persistedRecipient = null;
        await _storage.delete(key: 'elbench.push.recipient');
      }
      return;
    }
    if (_persistedRecipient != id) {
      _persistedRecipient = id;
      await _storage.write(key: 'elbench.push.recipient', value: id);
    }
    if (available && enabled && changed) await _register();
    if (_pending != null) {
      final data = _pending!;
      _pending = null;
      _open(data);
    }
  }

  Future<void> enable() async {
    if (!available) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      enabled =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (enabled) {
        await _register();
      } else {
        state =
            'Notifications are denied. Enable them in the device Settings app.';
      }
    } catch (_) {
      state = 'Unable to register this device. Please try again.';
    }
    notifyListeners();
  }

  Future<void> _register() async {
    if (_user == null) return;
    registered = false;
    try {
      if (Platform.isIOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        state =
            'Waiting for Apple push registration. Push requires APNs support on this device or simulator.';
        notifyListeners();
        return;
      }
      _token ??= await FirebaseMessaging.instance.getToken();
      if (_token == null) return;
      await api.send('POST', '/push/mobile', {
        'token': _token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'locale': _locale ?? 'en',
      });
      registered = true;
      state = 'Notifications are enabled for this account.';
    } catch (_) {
      state =
          'Device permission is granted, but server registration failed. Tap Enable to retry.';
    }
    notifyListeners();
  }

  Future<void> unbind() async {
    if (_token != null && _user != null) {
      // Best effort: the server also removes this device's subscription on
      // logout, and an expired session cannot authorize the request at all.
      try {
        await api.send('DELETE', '/push/mobile', {'token': _token});
      } catch (_) {}
    }
    _user = null;
    _persistedRecipient = null;
    registered = false;
    await _storage.delete(key: 'elbench.push.recipient');
    await _notifications.cancelAll();
  }

  bool _matches(Json data) =>
      _user != null && value(data['recipient']) == _user;
  void _open(Json data) {
    if (!_matches(data)) return;
    try {
      final path = api.safePath(value(data['url'], '/notifications'));
      if (RegExp(
        r'^/(notifications(?:/|\?|$)|ask/\d+|community/posts/\d+|question\?|profile(?:\?|$)|users/\d+)',
      ).hasMatch(path)) {
        navigate(path);
      }
    } catch (_) {}
  }

  Future<void> _foreground(RemoteMessage message) async {
    if (!_matches(message.data)) return;
    await _notifications.show(
      message.messageId.hashCode & 0x7fffffff,
      message.notification?.title ?? value(message.data['title'], 'ElBench'),
      message.notification?.body ?? value(message.data['body']),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          importance: Importance.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
