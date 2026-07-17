// Native-platform stub for oasis_iframe_web.dart.
// Imported automatically on iOS / Android / desktop via the conditional import
// in palm_oasis_viewer.dart. All methods are no-ops.

/// No-op stand-in for [OasisWebImpl] on native platforms (iOS/Android/desktop).
/// The WebView path in palm_oasis_viewer.dart is used instead.
class OasisWebImpl {
  bool isReady = false;
  bool hasFailed = false;
  void Function()? onStateChange;

  void setVisiblePalms(int count) {}
  void dispose() {}
}

/// Returns a no-op impl; the real iframe registration is web-only.
OasisWebImpl createOasisView(String viewId, String src) => OasisWebImpl();
