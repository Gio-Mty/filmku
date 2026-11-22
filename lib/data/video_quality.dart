// Pilihan kualitas untuk video dari Wikimedia Commons.
// Wikimedia menyediakan transcode VP9 dengan pola nama `<file>.<kualitas>.vp9.webm`;
// untuk film Blender yang tersedia 240p, 480p, dan 1080p.

const defaultQuality = '480p';
const _available = ['240p', '480p', '1080p'];
final _pattern = RegExp(r'\.(\d+p)\.vp9\.webm$');

/// Kualitas yang bisa dipilih untuk [url]; kosong jika sumbernya bukan Wikimedia.
List<String> qualitiesFor(String url) =>
    _pattern.hasMatch(url) ? _available : const [];

String urlForQuality(String url, String quality) =>
    url.replaceFirst(_pattern, '.$quality.vp9.webm');

String qualityLabel(String quality) => switch (quality) {
      '240p' => '240p · Hemat data',
      '480p' => '480p · Standar',
      '1080p' => '1080p · HD',
      _ => quality,
    };
