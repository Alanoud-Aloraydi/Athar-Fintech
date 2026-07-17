// Flutter-Web-only iframe helper for the Palm Oasis scene.
// Imported conditionally in palm_oasis_viewer.dart via:
//   import 'oasis_iframe_web.dart' if (dart.library.io) 'oasis_iframe_stub.dart';
//
// On Flutter Web this file is compiled; on native the stub is used instead.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// Registers an <iframe> as a platform view and returns a controller that can
/// communicate with the oasis_viewer.html page via window.postMessage.
OasisWebImpl createOasisView(String viewId, String src) {
  final el = html.IFrameElement()
    ..src = src
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..setAttribute('scrolling', 'no')
    ..setAttribute('allow', 'fullscreen');

  ui_web.platformViewRegistry.registerViewFactory(viewId, (_) => el);
  return OasisWebImpl._(el);
}

/// Controller that wraps the registered IFrameElement, exposing the same
/// surface that [PalmOasisController] calls on the web path.
class OasisWebImpl {
  final html.IFrameElement _el;
  StreamSubscription<html.MessageEvent>? _sub;

  bool isReady = false;
  bool hasFailed = false;

  /// Called by [PalmOasisViewer] to trigger a rebuild when state changes.
  void Function()? onStateChange;

  OasisWebImpl._(this._el) {
    _sub = html.window.onMessage.listen(_handleMessage);
  }

  void _handleMessage(html.MessageEvent e) {
    try {
      final raw = e.data;
      final Map<String, dynamic> data;
      if (raw is String) {
        data = jsonDecode(raw) as Map<String, dynamic>;
      } else {
        // JS object arrives as a JsObject / plain Map depending on the runtime.
        data = Map<String, dynamic>.from(raw as Map);
      }
      if (data['event'] == 'ready' && !isReady) {
        isReady = true;
        onStateChange?.call();
      } else if (data['event'] == 'error' && !hasFailed) {
        hasFailed = true;
        onStateChange?.call();
      }
    } catch (_) {
      // Malformed payload — ignore.
    }
  }

  /// Tells the Spline scene how many palms should be visible.
  void setVisiblePalms(int count) {
    try {
      _el.contentWindow?.postMessage(
        // Post as a plain JS object; oasis_viewer.html receives it via
        // window.addEventListener('message', ...).
        {'cmd': 'setVisiblePalmCount', 'count': count.clamp(1, 12)},
        '*',
      );
    } catch (_) {}
  }

  void dispose() => _sub?.cancel();
}
