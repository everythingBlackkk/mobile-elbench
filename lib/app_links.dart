/// Converts an incoming platform link to a supported, local content page.
/// External destinations and write/account-management routes are never opened.
String? appLinkPath(String location) {
  try {
    return _appLinkPath(location);
  } on FormatException {
    return null;
  }
}

String? _appLinkPath(String location) {
  if (location.isEmpty ||
      location.length > 4096 ||
      RegExp(r'[\x00-\x20\x7f\\]').hasMatch(location) ||
      RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(location)) {
    return null;
  }
  // Uri.tryParse can normalize bad percent escapes, while decoded getters
  // can still throw on invalid UTF-8. Validate the original input first.
  if (RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(Uri.decodeComponent(location))) {
    return null;
  }
  final uri = Uri.tryParse(location);
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  String path;
  if (uri.scheme == 'https') {
    const hosts = {
      'elbench.com',
      'www.elbench.com',
      'sahbak.site',
      'www.sahbak.site',
    };
    if (!hosts.contains(uri.host) || uri.port != 443) return null;
    path = uri.path;
  } else if (uri.scheme == 'elbench') {
    if (!uri.hasAuthority || uri.hasPort) return null;
    path = uri.host.isEmpty ? uri.path : '/${uri.host}${uri.path}';
  } else if (uri.scheme.isEmpty &&
      !uri.hasAuthority &&
      location.startsWith('/') &&
      !location.startsWith('//')) {
    path = uri.path;
  } else {
    return null;
  }

  const id = r'[1-9][0-9]{0,18}';
  final announcement = RegExp('^/announcements/($id)/?\$').firstMatch(path);
  if (announcement != null) {
    path = '/notifications/announcements/${announcement[1]}';
  }
  final query = <String, String>{};
  for (final entry in uri.queryParametersAll.entries) {
    if (entry.value.length != 1) continue;
    final value = entry.value.single;
    if (const {
          'id',
          'community_id',
          'focus_comment',
          'thread',
          'notice',
        }.contains(entry.key) &&
        RegExp('^$id\$').hasMatch(value)) {
      query[entry.key] = value;
    } else if (entry.key == 'lang' && const {'en', 'ar'}.contains(value)) {
      query[entry.key] = value;
    } else if (entry.key == 'tab' &&
        const {'posts', 'comments', 'asks'}.contains(value)) {
      query[entry.key] = value;
    }
  }

  final community = RegExp('^/community/($id)/?\$').firstMatch(path);
  if (community != null) {
    path = '/forum';
    query['community_id'] = community[1]!;
  } else {
    if (path.endsWith('/') && path != '/') {
      path = path.substring(0, path.length - 1);
    }
    final supported =
        path == '/community' ||
        RegExp('^/users/$id\$').hasMatch(path) ||
        RegExp('^/community/posts/$id\$').hasMatch(path) ||
        RegExp('^/ask/$id\$').hasMatch(path) ||
        RegExp('^/notifications/announcements/$id\$').hasMatch(path) ||
        RegExp('^/community/$id/(notifications|materials)\$').hasMatch(path) ||
        RegExp('^/community/materials/$id\$').hasMatch(path) ||
        (path == '/forum' && query.containsKey('community_id')) ||
        (path == '/question' && query.containsKey('id'));
    if (!supported) return null;
  }

  final fragment =
      RegExp('^(comment|answer|notice)-$id\$').hasMatch(uri.fragment)
      ? uri.fragment
      : '';
  return Uri(
    path: path,
    queryParameters: query.isEmpty ? null : query,
    fragment: fragment.isEmpty ? null : fragment,
  ).toString();
}
