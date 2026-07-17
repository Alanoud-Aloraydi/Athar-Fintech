import 'dart:async';
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
    if (!_sceneReady) return;
    final clamped = count.clamp(1, 12);
    if (kIsWeb) {
      _webImpl?.setVisiblePalms(clamped);
    } else {
      try {
        await _wvc?.runJavaScript('window.setVisiblePalmCount($clamped);');
      } catch (_) {
        // JS channel unavailable (e.g. WebView torn down) -- non-fatal.
      }
    }
  }
}

/// Embeds the Spline "Palm Oasis" scene.
///
/// On **Flutter Web** the asset is loaded in an `<iframe>` via
/// [HtmlElementView]; communication uses `window.postMessage`.
/// On **native** platforms a [WebViewWidget] is used with the existing
/// `OasisBridge` JS channel.
///
/// If the asset is missing, the runtime CDN is unreachable, or any other
/// error occurs, a graceful "3D view unavailable" message is shown and
/// the rest of the app continues to work normally.
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
  String? _failureReason;

  // If the scene hasn't reported "ready" within this duration, give up and
  // show the fallback rather than leaving the user with an indefinite spinner.
  static const _sceneTimeout = Duration(seconds: 20);
  Timer? _timeoutTimer;

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
    _viewId = 'oasis-iframe-$hashCode';
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
    try {
      final wvc = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (WebResourceError error) {
              // Only treat main-frame errors as fatal; sub-resource errors
              // (e.g. a missing texture) are handled inside the JS itself.
              if (error.isForMainFrame ?? false) {
                _markFailed('WebResourceError: ${error.description}');
              }
            },
          ),
        )
        ..addJavaScriptChannel('OasisBridge', onMessageReceived: _onBridgeMsg)
        ..loadFlutterAsset('assets/oasis/oasis_viewer.html');

      _wvc = wvc;
      _ctrl = PalmOasisController._native(wvc);

      // Give the scene a fixed window to load; cancel if "ready" arrives first.
      _timeoutTimer = Timer(_sceneTimeout, () {
        if (mounted && !_ctrl._sceneReady) {
          _markFailed('Scene load timed out after ${_sceneTimeout.inSeconds}s');
        }
      });

      widget.onControllerReady(_ctrl);
    } catch (e) {
      // If WebView construction itself fails (unsupported platform, etc.),
      // fall back gracefully rather than crashing the entire screen.
      // Set fields directly (no setState) — the first build picks them up.
      _ctrl = PalmOasisController._native(null);
      _loadFailed = true;
      _failureReason = 'WebView init failed: $e';
      widget.onControllerReady(_ctrl);
    }
  }

  // ── native JS bridge ─────────────────────────────────────────────────────

  void _onBridgeMsg(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      final event = data['event'] as String?;
      if (event == 'ready') {
        _timeoutTimer?.cancel();
        if (mounted) setState(() => _ctrl._sceneReady = true);
      } else if (event == 'error') {
        _markFailed(data['message']?.toString() ?? 'unknown scene error');
      }
    } catch (_) {
      // Malformed bridge payload — non-fatal.
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  void _markFailed(String reason) {
    _timeoutTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _loadFailed = true;
      _failureReason = reason;
    });
  }

  bool get _isReady => kIsWeb ? (_webImpl?.isReady ?? false) : _ctrl._sceneReady;
  bool get _hasFailed => kIsWeb ? (_webImpl?.hasFailed ?? false) : _loadFailed;

  @override
  void dispose() {
    _timeoutTimer?.cancel();
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

            // ── scene widget ──────────────────────────────────────────────
            if (kIsWeb && _viewId != null)
              HtmlElementView(viewType: _viewId!)
            else if (!kIsWeb && _wvc != null && !_hasFailed)
              WebViewWidget(controller: _wvc!),

            // ── loading spinner ───────────────────────────────────────────
            if (!_isReady && !_hasFailed)
              const Center(child: CircularProgressIndicator()),

            // ── error fallback ────────────────────────────────────────────
            if (_hasFailed)
              _FallbackScene(reason: _failureReason),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the 3D scene whenever loading fails for any reason.
/// Intentionally styled to blend with the app rather than look like an error.
class _FallbackScene extends StatelessWidget {
  final String? reason;
  const _FallbackScene({super.key, this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primaryLight.withValues(alpha: 0.15),
            AppColors.card,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.park_rounded,
                size: 56,
                color: AppColors.primaryLight.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                'المشهد ثلاثي الأبعاد غير متاح',
                style: AppTextStyles.label,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'تحقق من اتصالك بالإنترنت أو حاول لاحقاً',
                style: AppTextStyles.small,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
