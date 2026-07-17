import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';

/// Controller handed back via [PalmOasisViewer.onControllerReady], letting
/// the parent screen (FarmScreen) drive the 3D scene: set the real palm
/// count once Oasis data loads, or temporarily preview a hypothetical
/// count from the transaction simulator.
class PalmOasisController {
  final WebViewController _webViewController;
  bool _sceneReady = false;

  PalmOasisController._(this._webViewController);

  bool get isSceneReady => _sceneReady;

  /// Sets Palm_01..Palm_0[count] visible and hides the rest. Safe to call
  /// before the scene finishes loading -- queued calls before `ready`
  /// are simply dropped since `oasis_viewer.html` re-applies the real
  /// count itself once `setVisiblePalmCount` becomes available; callers
  /// should re-invoke this once [isSceneReady] flips true if needed.
  Future<void> setVisiblePalms(int count) async {
    final clamped = count.clamp(1, 12);
    await _webViewController.runJavaScript('window.setVisiblePalmCount($clamped);');
  }
}

/// Embeds the Spline "Palm Oasis" scene (see assets/oasis/oasis_viewer.html)
/// in a WebView. All 12 palms exist in the exported scene, named
/// "Palm_01".."Palm_12"; the host page hides all but the current count via
/// `getObjectByName(...).visible = ...` (never findObjectByName /
/// setVariable, per the scene's export notes).
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
  late final WebViewController _controller;
  late final PalmOasisController _oasisController;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'OasisBridge',
        onMessageReceived: _onBridgeMessage,
      )
      ..loadFlutterAsset('assets/oasis/oasis_viewer.html');

    _oasisController = PalmOasisController._(_controller);
    widget.onControllerReady(_oasisController);
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      if (data['event'] == 'ready') {
        setState(() => _oasisController._sceneReady = true);
      } else if (data['event'] == 'error') {
        setState(() => _loadFailed = true);
      }
    } catch (_) {
      // Malformed bridge payload -- non-fatal, the scene keeps running.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.card),
            WebViewWidget(controller: _controller),
            if (!_oasisController.isSceneReady && !_loadFailed)
              const Center(child: CircularProgressIndicator()),
            if (_loadFailed)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.park_rounded, size: 40, color: AppColors.primaryLight),
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
