import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'vidfast_controller.dart';

@JS('JSON.stringify')
external String _stringify(JSAny? obj);

Widget buildEmbedView({
  required String url,
  required String filmId,
  required VidFastController controller,
  VoidCallback? onOpenExternal,
}) {
  final viewType = 'iframe-embed-$filmId';
  web.HTMLIFrameElement? activeIframe;

  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int id) {
      final iframe = web.HTMLIFrameElement()
        ..src = url
        ..id = 'vidfast-player-$filmId'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'encrypted-media; autoplay; fullscreen'
        ..allowFullscreen = true;
      activeIframe = iframe;
      return iframe;
    },
  );

  controller.commandDispatcher = (command, params) {
    try {
      final payload = {'command': command, ...params};
      final jsObj = payload.jsify();
      activeIframe?.contentWindow?.postMessage(jsObj, '*'.toJS);
    } catch (_) {}
  };

  web.window.addEventListener(
    'message',
    (web.MessageEvent event) {
      try {
        final rawData = event.data;
        if (rawData == null) return;
        final jsonStr = _stringify(rawData);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (map['type'] == 'PLAYER_EVENT' && map['data'] is Map) {
          controller.handleEvent(map['data'] as Map<String, dynamic>);
        } else if (map['type'] == 'MEDIA_DATA' && map['data'] is Map) {
          controller.handleMediaData(map['data'] as Map<String, dynamic>);
        }
      } catch (_) {}
    }.toJS,
  );

  return HtmlElementView(viewType: viewType);
}
