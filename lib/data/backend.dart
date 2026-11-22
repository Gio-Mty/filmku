import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_version.dart';
import '../models/film.dart';
import '../models/series.dart';
import '../models/tmdb_detail.dart';
import '../models/tv_detail.dart';

/// Client untuk backend filmku (folder backend/, FastAPI di port 8000).
///
/// Alamat bisa diganti saat build, misalnya untuk HP fisik:
///   flutter run --dart-define=BACKEND_URL=http://192.168.1.10:8000
class Backend {
  static const _override = String.fromEnvironment('BACKEND_URL');

  static String? _workingBaseUrl;

  static List<String> get _candidates {
    if (_override.isNotEmpty) return [_override];
    if (kIsWeb) return ['https://filmku-rho.vercel.app', 'http://localhost:8000'];
    if (defaultTargetPlatform == TargetPlatform.android) {
      return [
        'https://filmku-rho.vercel.app', // Vercel Cloud Server (Bisa diakses dari mana saja tanpa Wi-Fi laptop)
        'http://192.168.1.4:8000',       // Wi-Fi LAN Laptop saat ini
        'http://127.0.0.1:8000',         // HP Fisik via USB (adb reverse)
        'http://localhost:8000',         // Fallback
        'http://10.0.2.2:8000',          // Emulator Android
        'http://10.188.148.47:8000',     // Wi-Fi LAN cadangan
      ];
    }
    return ['https://filmku-rho.vercel.app', 'http://localhost:8000'];
  }

  static String get baseUrl => _workingBaseUrl ?? _candidates.first;

  static final _cache = <String, Future<dynamic>>{};

  static Future<dynamic> _get(String path) {
    return _cache[path] ??= _fetch(path)
      ..then(
        (_) {},
        onError: (_) {
          // Jangan simpan kegagalan, supaya bisa dicoba lagi.
          _cache.remove(path);
        },
      );
  }

  static Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    final targets = _workingBaseUrl != null ? [_workingBaseUrl!] : _candidates;

    for (final base in targets) {
      try {
        final res = await http
            .post(
              Uri.parse('$base$path'),
              headers: {'Content-Type': 'application/json'},
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(const Duration(seconds: 5));

        _workingBaseUrl = base;
        final Object? resBody;
        try {
          resBody = jsonDecode(utf8.decode(res.bodyBytes));
        } on FormatException {
          throw BackendException(
            'Respons backend tidak dikenal (HTTP ${res.statusCode})',
          );
        }

        if (res.statusCode != 200) {
          final detail = resBody is Map ? resBody['detail'] : null;
          throw BackendException(
            detail is String
                ? detail
                : 'Backend membalas HTTP ${res.statusCode}',
          );
        }
        return resBody;
      } on Exception catch (e) {
        if (targets.length == 1 && e is BackendException) rethrow;
        continue;
      }
    }

    _workingBaseUrl = null;
    throw BackendException(
      'Backend filmku tidak bisa dihubungi. Pastikan uvicorn berjalan di folder backend.',
    );
  }

  static Future<dynamic> _fetch(String path) async {
    final targets = _workingBaseUrl != null ? [_workingBaseUrl!] : _candidates;

    for (final base in targets) {
      try {
        final res = await http
            .get(Uri.parse('$base$path'))
            .timeout(const Duration(seconds: 5));

        _workingBaseUrl = base;
        final Object? body;
        try {
          body = jsonDecode(utf8.decode(res.bodyBytes));
        } on FormatException {
          throw BackendException(
            'Respons backend tidak dikenal (HTTP ${res.statusCode})',
          );
        }

        if (res.statusCode != 200) {
          final detail = body is Map ? body['detail'] : null;
          throw BackendException(
            detail is String
                ? detail
                : 'Backend membalas HTTP ${res.statusCode}',
          );
        }
        return body;
      } on Exception catch (e) {
        if (targets.length == 1 && e is BackendException) rethrow;
        continue;
      }
    }

    _workingBaseUrl = null;
    throw BackendException(
      'Backend filmku tidak bisa dihubungi. Pastikan uvicorn berjalan di folder backend.',
    );
  }

  static Future<List<Series>> catalog({int page = 1, String? query}) async {
    final q = query == null || query.isEmpty
        ? ''
        : '&q=${Uri.encodeQueryComponent(query)}';
    final data =
        await _get('/api/catalog?page=$page$q') as Map<String, dynamic>;
    return (data['results'] as List)
        .map((j) => Series.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Film populer dari TMDB (lewat backend). Hanya metadata; tidak ada video.
  static Future<List<Film>> tmdbPopular({int page = 1}) async {
    final data =
        await _get('/api/tmdb/popular?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data);
  }

  static Future<List<Film>> tmdbTrending({int page = 1}) async {
    final data =
        await _get('/api/tmdb/trending?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data);
  }

  static Future<List<Film>> tmdbTopRated({int page = 1}) async {
    final data =
        await _get('/api/tmdb/top_rated?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data);
  }

  static Future<List<Film>> tmdbDiscover({String? genre, int page = 1}) async {
    final q = genre != null && genre.isNotEmpty ? '&with_genres=$genre' : '';
    final data =
        await _get('/api/tmdb/discover?page=$page$q') as Map<String, dynamic>;
    return _tmdbFilms(data);
  }

  /// Serial Drama Korea (Drakor) populer dari TMDB (lewat backend).
  static Future<List<Film>> tmdbKDrama({int page = 1}) async {
    final data =
        await _get('/api/tmdb/kdrama?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data, defaultIsTv: true);
  }

  /// Drakor Sedang Tayang (On-Going).
  static Future<List<Film>> tmdbKDramaAiring({int page = 1}) async {
    final data =
        await _get('/api/tmdb/kdrama/airing?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data, defaultIsTv: true);
  }

  /// Drakor Rating Tertinggi Sepanjang Masa (All-Time Classics).
  static Future<List<Film>> tmdbKDramaTopRated({int page = 1}) async {
    final data =
        await _get('/api/tmdb/kdrama/top_rated?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data, defaultIsTv: true);
  }

  /// Drakor Romantis & Komedi Romantis.
  static Future<List<Film>> tmdbKDramaRomance({int page = 1}) async {
    final data =
        await _get('/api/tmdb/kdrama/romance?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data, defaultIsTv: true);
  }

  /// Drakor Misteri, Kriminal & Thriller.
  static Future<List<Film>> tmdbKDramaThriller({int page = 1}) async {
    final data =
        await _get('/api/tmdb/kdrama/thriller?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data, defaultIsTv: true);
  }

  /// Detail serial TV / Drakor dari TMDB.
  static Future<TvDetail> tmdbTvDetail(int tvId) async {
    final data = await _get('/api/tmdb/tv/$tvId') as Map<String, dynamic>;
    return TvDetail.fromJson(data);
  }

  /// Daftar episode serial TV untuk musim tertentu dari TMDB.
  static Future<List<TvEpisode>> tmdbTvSeason(
    int tvId,
    int seasonNumber,
  ) async {
    final data =
        await _get('/api/tmdb/tv/$tvId/season/$seasonNumber') as List<dynamic>;
    return data
        .map((e) => TvEpisode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Film dari database Supabase (tabel tmdb_movies).
  static Future<List<Film>> supabaseMovies({int page = 1}) async {
    final data =
        await _get('/api/supabase/movies?page=$page') as Map<String, dynamic>;
    return _tmdbFilms(data);
  }

  static Future<List<Film>> tmdbSearch(String query, {int page = 1}) async {
    final data = await _get(
      '/api/tmdb/search?q=${Uri.encodeQueryComponent(query)}&page=$page',
    ) as Map<String, dynamic>;
    return _tmdbFilms(data);
  }

  static List<Film> _tmdbFilms(
    Map<String, dynamic> data, {
    bool defaultIsTv = false,
  }) =>
      (data['results'] as List)
          .cast<Map<String, dynamic>>()
          .where((m) => m['poster'] != null)
          .map(
            (m) {
              final isTv = defaultIsTv || (m['media_type'] == 'tv');
              final idNum = m['id'] as int;
              return Film(
                id: isTv ? 'tmdb-tv-$idNum' : 'tmdb-$idNum',
                title: m['title'] as String,
                year: (m['year'] as int?) ?? 0,
                duration: '',
                genres: List<String>.from(m['genres'] as List),
                rating: (m['rating'] as num).toDouble(),
                quality: 'HD',
                synopsis: (m['overview'] as String).isEmpty
                    ? 'Sinopsis belum tersedia.'
                    : m['overview'] as String,
                posterUrl: m['poster'] as String,
                videoUrl: null,
                license: 'Vidfast HD',
                credit: 'Data: TMDB | Pemutar: Vidfast',
                tvId: isTv ? idNum : null,
                seasonNumber: isTv ? 1 : null,
                episodeNumber: isTv ? 1 : null,
              );
            },
          )
          .toList();

  /// Pemain, trailer, dan layanan streaming resmi di Indonesia untuk satu film TMDB.
  static Future<TmdbDetail> tmdbDetail(int id) async {
    final data = await _get('/api/tmdb/movie/$id') as Map<String, dynamic>;
    return TmdbDetail.fromJson(data);
  }

  static Future<SeriesEpisodes> episodes(String slug) async {
    final data = await _get(
      '/api/episodes?slug=${Uri.encodeQueryComponent(slug)}',
    ) as Map<String, dynamic>;
    return SeriesEpisodes.fromJson(data);
  }

  /// Membuat room Nonton Bareng (Watch Party) baru
  static Future<Map<String, dynamic>> createWatchParty() async {
    final data = await _post('/api/watchparty/create') as Map<String, dynamic>;
    return data;
  }

  /// Membaca status room Nonton Bareng terkini
  static Future<Map<String, dynamic>> getWatchParty(String roomId) async {
    final data = await _fetch('/api/watchparty/$roomId') as Map<String, dynamic>;
    return data;
  }

  /// Sinkronisasi tindakan playback (play/pause/seek) ke room Nonton Bareng
  static Future<Map<String, dynamic>> syncWatchParty(
    String roomId,
    String action,
    double time,
  ) async {
    final data = await _post(
      '/api/watchparty/$roomId/sync',
      {'action': action, 'time': time},
    ) as Map<String, dynamic>;
    return data;
  }

  /// Memeriksa pembaruan versi aplikasi
  static Future<AppVersion> checkAppVersion() async {
    final data = await _fetch('/api/app/version') as Map<String, dynamic>;
    return AppVersion.fromJson(data);
  }
}

class BackendException implements Exception {
  BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}
