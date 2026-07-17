import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';

// On Flutter Web  → uses HtmlElementView + dart:html postMessage.
// On native       → uses WebView (existing behaviour, unchanged).
import 'oasis_iframe_web.dart' if (dart.library.io) 'oasis_iframe_stub.dart';

/// Drives the Oasis 3D scene from the parent screen (FarmScreen).
/// Works on both Flutter Web (HtmlElementView/iframe) and native (WebView).
class PalmOasisController {
  // One of these is set depending on the platform:
  final WebViewController? _wvc; // native
  OasisWebImpl? _webImpl; // web (settable so initState can assign after ctor)

  bool _sceneReady = false;
  bool get isSceneReady => _sceneReady;

  PalmOasisController._native(this._wvc) : _webImpl = null;
  PalmOasisController._web(this._webImpl) : _wvc = null;

  /// Shows [count] palms (clamped 1–12). Safe to call before the scene is
  /// ready — the call is simply dropped; callers should retry once
  /// [isSceneReady] is true.
  Future<void> setVisiblePalms(int count) async {
    final clamped = count.clamp(1, 12);
    if (kIsWeb) {
      _webImpl?.setVisiblePalms(clamped);
    } else {
      await _wvc?.runJavaScript('window.setVisiblePalmCount($clamped);');
    }
  }
}

/// Embeds the Spline "Palm Oasis" scene.
///
/// On **Flutter Web** the asset is loaded in an `<iframe>` via
/// [HtmlElementView]; communication uses `window.postMessage`.
/// On **native** platforms a [WebViewWidget] is used with the existing
/// `OasisBridge` JS channel.
class PalmOasisViewer extends StatefulWidget {
  final double height;
  final ValueChanged<PalmOasisController> onControllerReady;

  const PalmOasisViewer({
    super.key,
    required this.onControllerReady,
    this.height = 280,
  });

  @override
  State<PalmOasisViewer> createState() => _PalmOasisViewerState();
}

class _PalmOasisViewerState extends State<PalmOasisViewer> {
  // --- native ---
  WebViewController? _wvc;
  // --- web ---
  OasisWebImpl? _webImpl;
  String? _viewId;

  late final PalmOasisController _ctrl;
  bool _loadFailed = false;

  // ── init ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initWeb();
    } else {
      _initNative();
    }
  }

  void _initWeb() {
    _viewId = 'oasis-iframe-${hashCode}';
    final impl = createOasisView(_viewId!, '/assets/oasis/oasis_viewer.html');
    _webImpl = impl;
    _ctrl = PalmOasisController._web(impl);
    impl.onStateChange = () {
      if (!mounted) return;
      _ctrl._sceneReady = impl.isReady;
      setState(() {});
    };
    widget.onControllerReady(_ctrl);
  }

  void _initNative() {
    final wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('OasisBridge', onMessageReceived: _onBridgeMsg)
      ..loadFlutterAsset('assets/oasis/oasis_viewer.html');
    _wvc = wvc;
    _ctrl = PalmOasisController._native(wvc);
    widget.onControllerReady(_ctrl);
  }

  // ── native JS bridge ─────────────────────────────────────────────────────

  void _onBridgeMsg(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      if (data['event'] == 'ready') {
        setState(() => _ctrl._sceneReady = true);
      } else if (data['event'] == 'error') {
        setState(() => _loadFailed = true);
      }
    } catch (_) {}
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  bool get _isReady => kIsWeb ? (_webImpl?.isReady ?? false) : _ctrl._sceneReady;
  bool get _hasFailed => kIsWeb ? (_webImpl?.hasFailed ?? false) : _loadFailed;

  @override
  void dispose() {
    _webImpl?.dispose();
    super.dispose();
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background fill while the scene loads.
            Container(color: AppColors.card),

            // ── scene widget ────────────────────────────────────────────
            if (kIsWeb && _viewId != null)
              HtmlElementView(viewType: _viewId!)
            else if (!kIsWeb && _wvc != null)
              WebViewWidget(controller: _wvc!),

            // ── loading spinner ─────────────────────────────────────────
            if (!_isReady && !_hasFailed)
              const Center(child: CircularProgressIndicator()),

            // ── error fallback ──────────────────────────────────────────
            if (_hasFailed)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.park_rounded,
                        size: 40,
                        color: AppColors.primaryLight,
                      ),
                      const SizedBox(height: 8),
                      Text('تعذّر تحميل مشهد الواحة', style: AppTextStyles.body),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
