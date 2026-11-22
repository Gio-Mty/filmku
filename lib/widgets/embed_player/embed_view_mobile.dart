import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme.dart';
import 'vidfast_controller.dart';

Widget buildEmbedView({
  required String url,
  required String filmId,
  required VidFastController controller,
  VoidCallback? onOpenExternal,
}) {
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  if (isMobile) {
    return _MobileWebView(url: url, controller: controller);
  }

  return _DesktopFallbackView(url: url, onOpenExternal: onOpenExternal);
}

class _MobileWebView extends StatefulWidget {
  const _MobileWebView({required this.url, required this.controller});
  final String url;
  final VidFastController controller;

  @override
  State<_MobileWebView> createState() => _MobileWebViewState();
}

class _MobileWebViewState extends State<_MobileWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'VidFastBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          try {
            final map = jsonDecode(msg.message) as Map<String, dynamic>;
            if (map['type'] == 'PLAYER_EVENT' && map['data'] is Map) {
              widget.controller
                  .handleEvent(map['data'] as Map<String, dynamic>);
            } else if (map['type'] == 'MEDIA_DATA' && map['data'] is Map) {
              widget.controller
                  .handleMediaData(map['data'] as Map<String, dynamic>);
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            // Tolak skema berbahaya selain http & https (misal intent://, market://)
            if (uri.scheme != 'http' && uri.scheme != 'https') {
              return NavigationDecision.prevent;
            }

            // Izinkan sub-frame internal pemutar video
            if (!request.isMainFrame) {
              return NavigationDecision.navigate;
            }

            final host = uri.host.toLowerCase();
            const allowedKeywords = [
              'vidfast',
              'vidsrc',
              'multiembed',
              'autoembed',
              '2embed',
              'superembed',
              'cloudstream',
              'rabbitstream',
              'megacloud',
              'stream',
              'player',
            ];

            if (allowedKeywords.any((k) => host.contains(k))) {
              return NavigationDecision.navigate;
            }

            // Blokir otomatis semua redirect ke link phishing, judi, atau pop-up eksternal!
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _controller.runJavaScript("""
              (function() {
                // Blokir popup liar dari iklan pihak ketiga
                window.open = function() { return null; };
                if (window.__vidfast_bridge_injected) return;
                window.__vidfast_bridge_injected = true;
                window.addEventListener('message', function(event) {
                  if (event.data && (event.data.type === 'PLAYER_EVENT' || event.data.type === 'MEDIA_DATA')) {
                    if (window.VidFastBridge) {
                      window.VidFastBridge.postMessage(JSON.stringify(event.data));
                    }
                  }
                });
              })();
            """);
          },
          onWebResourceError: (err) {
            if (mounted && (err.isForMainFrame ?? true)) {
              setState(() {
                _loading = false;
                _error = err.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    widget.controller.commandDispatcher = (command, params) {
      final jsonParams = jsonEncode({'command': command, ...params});
      _controller.runJavaScript("""
        (function() {
          var payload = $jsonParams;
          window.postMessage(payload, '*');
          var iframes = document.getElementsByTagName('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(payload, '*');
            } catch(e) {}
          }
        })();
      """);
    };
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          ),
        if (_error != null)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat pemutar: $_error',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DesktopFallbackView extends StatelessWidget {
  const _DesktopFallbackView({required this.url, this.onOpenExternal});
  final String url;
  final VoidCallback? onOpenExternal;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline_rounded,
              size: 80,
              color: AppColors.accent,
            ),
            const SizedBox(height: 16),
            const Text(
              'Pemutar Vidfast',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Di versi Desktop (Windows), klik tombol di bawah untuk memutar di browser:',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Buka Pemutar di Browser'),
              onPressed: onOpenExternal,
            ),
          ],
        ),
      ),
    );
  }
}
