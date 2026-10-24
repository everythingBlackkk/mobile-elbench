import 'package:flutter/services.dart';

Future<bool> shareNative(String url, String title) async {
  try {
    return await const MethodChannel(
          'elbench/native-share',
        ).invokeMethod<bool>('share', {'url': url, 'title': title}) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
