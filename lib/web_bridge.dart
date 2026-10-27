import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Thin wrappers over browser APIs used for saving and sharing (#9) and
/// the HTML loading screen (#10). All failures are swallowed: private
/// windows can block storage and clipboard.
abstract final class WebBridge {
  static const _key = 'tileCity.v1';

  static String? loadSaved() {
    try {
      return web.window.localStorage.getItem(_key);
    } catch (_) {
      return null;
    }
  }

  static void save(String value) {
    try {
      web.window.localStorage.setItem(_key, value);
    } catch (_) {}
  }

  /// The share payload in `#t=…`, if any.
  static String? sharedTown() {
    final h = web.window.location.hash;
    return h.startsWith('#t=') ? h.substring(3) : null;
  }

  /// Puts [code] in the address bar and returns the full link.
  static String shareLink(String code) {
    final loc = web.window.location;
    final url = '${loc.origin}${loc.pathname}#t=$code';
    try {
      web.window.history.replaceState(null, '', '#t=$code');
    } catch (_) {}
    return url;
  }

  static Future<bool> copy(String text) async {
    try {
      await web.window.navigator.clipboard.writeText(text).toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fades out and removes the HTML loader from index.html.
  static void hideLoader() {
    final el = web.document.getElementById('loader');
    if (el == null) return;
    el.classList.add('done');
    Future.delayed(const Duration(milliseconds: 600), () => el.remove());
  }
}
