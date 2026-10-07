/// Tidies a server address typed by a person. Returns the address without a trailing
/// slash (adding `https://` if no scheme was given), or null if it can't be an address.
String? normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  if (!text.contains('://')) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return null;
  if (uri.host.isEmpty || uri.hasQuery || uri.hasFragment) return null;
  final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
  return uri.replace(path: path).toString();
}

/// Plain http is fine for a server on your own network, not for one on the internet:
/// a student's location and schedule would travel unprotected.
bool isInsecureRemote(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'http') return false;
  final host = uri.host;
  return !(host == 'localhost' ||
      host == '10.0.2.2' || // the Android emulator's name for the computer it runs on
      host.startsWith('127.') ||
      host.startsWith('192.168.') ||
      host.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host) ||
      host.endsWith('.local'));
}
