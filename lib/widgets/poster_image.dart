import 'package:flutter/material.dart';

/// Gambar poster dari jaringan dengan placeholder saat gagal dimuat.
class PosterImage extends StatelessWidget {
  const PosterImage(this.url, {super.key});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // Di web, gambar diambil lewat XHR dan butuh header CORS. Poster Internet
      // Archive tidak mengirimnya, jadi saat ditolak pakai elemen <img> biasa.
      // Di Android/iOS parameter ini tidak berpengaruh.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFF1F1F23),
        child: Center(child: Icon(Icons.movie, color: Colors.white38, size: 40)),
      ),
    );
  }
}
