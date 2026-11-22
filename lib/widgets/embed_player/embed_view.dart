import 'package:flutter/widgets.dart';

import 'vidfast_controller.dart';
import 'embed_view_mobile.dart'
    if (dart.library.js_interop) 'embed_view_web.dart' as platform;

/// Membangun tampilan pemutar embed yang optimal sesuai platform:
/// - Web: Merender elemen <iframe> asli dengan izin full allowfullscreen & encrypted-media
/// - Android & iOS: Merender WebView native
/// - Desktop (Windows): Menampilkan fallback elegan dengan tombol buka di browser
Widget buildPlatformEmbedView({
  required String url,
  required String filmId,
  required VidFastController controller,
  VoidCallback? onOpenExternal,
}) {
  return platform.buildEmbedView(
    url: url,
    filmId: filmId,
    controller: controller,
    onOpenExternal: onOpenExternal,
  );
}
