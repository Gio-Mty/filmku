import 'film.dart';

/// Film dari koleksi `feature_films` Internet Archive.
///
/// [streamUrl] dan [subtitleUrl] kosong di hasil pencarian; diisi oleh
/// `ArchiveMovieService.fetchStreamDetails` saat detail film dibuka.
class ArchiveMovie {
  final String id; // `identifier` di Internet Archive
  final String title;
  final int? year;
  final String description;
  final int downloads;
  final String? streamUrl;
  final String? subtitleUrl;

  const ArchiveMovie({
    required this.id,
    required this.title,
    this.year,
    this.description = '',
    this.downloads = 0,
    this.streamUrl,
    this.subtitleUrl,
  });

  String get posterUrl => 'https://archive.org/services/img/$id';

  /// Field dari Internet Archive tidak konsisten: satu field bisa berupa
  /// String, angka, List, atau null. Semua dinormalkan di sini.
  factory ArchiveMovie.fromJson(Map<String, dynamic> json) {
    final id = _text(json['identifier']);
    final title = _text(json['title']);
    return ArchiveMovie(
      id: id,
      title: title.isEmpty ? id : title,
      year: _year(json['year']),
      description: _stripHtml(_text(json['description'], joiner: '\n\n')),
      downloads: _int(json['downloads']) ?? 0,
    );
  }

  ArchiveMovie withStream({String? streamUrl, String? subtitleUrl}) => ArchiveMovie(
        id: id,
        title: title,
        year: year,
        description: description,
        downloads: downloads,
        streamUrl: streamUrl,
        subtitleUrl: subtitleUrl,
      );

  /// Diubah ke [Film] supaya bisa memakai layar detail, Daftarku, dan pemutar yang sama.
  Film toFilm({List<String>? genres}) => Film(
        id: 'ia-$id',
        archiveId: id,
        title: title,
        year: year ?? 0,
        duration: '',
        genres: genres ?? const ['Klasik'],
        rating: 0,
        quality: '',
        synopsis: description,
        posterUrl: posterUrl,
        videoUrl: streamUrl,
        subtitleUrl: subtitleUrl,
        license: 'ARCHIVE',
        credit: 'Internet Archive · ${_formatCount(downloads)} kali diunduh',
      );
}

String _text(Object? v, {String joiner = ', '}) => switch (v) {
      null => '',
      String s => s.trim(),
      List l => l.map((e) => _text(e)).where((s) => s.isNotEmpty).join(joiner),
      _ => '$v'.trim(),
    };

int? _int(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s.trim()),
      List l when l.isNotEmpty => _int(l.first),
      _ => null,
    };

/// Tahun bisa ditulis "1950", "1950-05-01", "c. 1950", 1950, atau ["1950"].
int? _year(Object? v) {
  if (v is List) return v.isEmpty ? null : _year(v.first);
  if (v is num) return v.toInt();
  if (v is String) {
    final m = RegExp(r'\b(1[89]\d\d|20\d\d)\b').firstMatch(v);
    return m == null ? null : int.parse(m.group(1)!);
  }
  return null;
}

String _stripHtml(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

String _formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} jt';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)} rb';
  return '$n';
}
