import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/archive_movie.dart';

/// Film domain publik dari Internet Archive (koleksi `feature_films`).
/// Dipanggil langsung dari aplikasi; tidak perlu API key atau server filmku.
class ArchiveMovieService {
  ArchiveMovieService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  /// Subject yang disaring dari hasil genre (ada film dewasa yang ikut ditandai "romance").
  static const _adultSubjects = 'nudist OR nudity OR erotic OR erotica OR sexploitation OR adult';

  /// Daftar film, urut dari yang paling banyak diunduh. [query] mencari di judul.
  /// [subject] adalah ekspresi Lucene untuk genre (lihat `genres.dart`), bukan input pengguna.
  Future<List<ArchiveMovie>> fetchMovies({String? query, String? subject, int page = 1}) async {
    var q = 'collection:(feature_films) AND mediatype:(movies)';
    final term = _sanitize(query);
    if (term.isNotEmpty) q += ' AND title:($term)';
    if (subject != null) q += ' AND subject:($subject) AND NOT subject:($_adultSubjects)';

    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': q,
      'fl[]': const ['identifier', 'title', 'year', 'description', 'downloads'],
      'sort[]': 'downloads desc',
      'rows': '20',
      'page': '$page',
      'output': 'json',
    });
    final data = await _getJson(uri);
    final docs = (data['response'] as Map<String, dynamic>?)?['docs'] as List? ?? const [];
    return docs
        .whereType<Map<String, dynamic>>()
        .map(ArchiveMovie.fromJson)
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  /// Melengkapi [movie] dengan link video dan subtitle. Dipanggil saat detail dibuka.
  /// [ArchiveMovie.streamUrl] tetap null jika item tidak punya file mp4.
  Future<ArchiveMovie> fetchStreamDetails(ArchiveMovie movie) async {
    final data = await _getJson(Uri.https('archive.org', '/metadata/${movie.id}'));
    final files = (data['files'] as List? ?? const []).whereType<Map<String, dynamic>>();

    final video = pickMobileMp4(files);
    final subtitle = pickSubtitle(files, video?['name'] as String?);
    return movie.withStream(
      streamUrl: video == null ? null : _downloadUrl(movie.id, video['name'] as String),
      subtitleUrl:
          subtitle == null ? null : _downloadUrl(movie.id, subtitle['name'] as String),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw ArchiveException('Internet Archive membalas ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) throw ArchiveException('Respons tidak dikenal');
    return body;
  }

  // Nama file bisa berisi folder ("cd1/film.mp4"); encode tiap bagian, bukan garis miringnya.
  static String _downloadUrl(String id, String name) =>
      'https://archive.org/download/$id/${name.split('/').map(Uri.encodeComponent).join('/')}';

  // Buang karakter yang punya arti khusus di sintaks query Lucene.
  static String _sanitize(String? s) =>
      (s ?? '').replaceAll(RegExp(r'[()":\[\]{}^~*?\\/!+\-&|]'), ' ').trim();
}

/// Pilih mp4 yang ringan untuk HP.
///
/// Satu item bisa punya banyak mp4: master 1080p bergiga-giga, beberapa
/// resolusi, dan kadang potongan klip pendek. Karena itu, pertama ambil hanya
/// file yang durasinya mendekati film penuh, lalu yang terkecil dengan tinggi
/// minimal 240p (176p terlalu buram).
Map<String, dynamic>? pickMobileMp4(Iterable<Map<String, dynamic>> files) {
  final mp4s = files.where((f) {
    final name = (f['name'] as String? ?? '').toLowerCase();
    final format = (f['format'] as String? ?? '').toLowerCase();
    return name.endsWith('.mp4') && (format.contains('mpeg4') || format.contains('h.264'));
  }).toList();
  if (mp4s.isEmpty) return null;

  final longest = mp4s.map(_lengthSeconds).fold<double>(0, (a, b) => b > a ? b : a);
  var pool = longest > 0
      ? mp4s.where((f) => _lengthSeconds(f) >= longest * 0.8).toList()
      : mp4s;

  final sharpEnough = pool.where((f) {
    final h = _num(f['height']);
    return h == null || h == 0 || h >= 240;
  }).toList();
  if (sharpEnough.isNotEmpty) pool = sharpEnough;

  pool.sort((a, b) => (_num(a['size']) ?? double.infinity)
      .compareTo(_num(b['size']) ?? double.infinity));
  return pool.first;
}

/// Utamakan .vtt, lalu .srt; yang namanya sama dengan file video lebih dulu.
Map<String, dynamic>? pickSubtitle(Iterable<Map<String, dynamic>> files, String? videoName) {
  final subs = files.where((f) {
    final n = (f['name'] as String? ?? '').toLowerCase();
    return n.endsWith('.vtt') || n.endsWith('.srt');
  }).toList();
  if (subs.isEmpty) return null;

  final base = videoName?.toLowerCase().replaceFirst(RegExp(r'(_512kb)?\.mp4$'), '');
  int score(Map<String, dynamic> f) {
    final n = (f['name'] as String).toLowerCase();
    return (n.endsWith('.vtt') ? 2 : 0) + (base != null && n.startsWith(base) ? 1 : 0);
  }

  subs.sort((a, b) => score(b).compareTo(score(a)));
  return subs.first;
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// `length` bisa berupa detik ("4891.24") atau jam:menit:detik ("81:31").
double _lengthSeconds(Map<String, dynamic> f) {
  final raw = '${f['length'] ?? ''}';
  if (!raw.contains(':')) return double.tryParse(raw) ?? 0;
  return raw.split(':').fold<double>(0, (acc, p) => acc * 60 + (double.tryParse(p) ?? 0));
}

class ArchiveException implements Exception {
  ArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}
