import '../models/archive_movie.dart';
import '../models/film.dart';
import 'archive_service.dart';
import 'genres.dart';

/// Film dari Internet Archive, sudah diubah ke [Film] dan di-cache selama app berjalan.
class Api {
  static final archive = ArchiveMovieService();
  static final _cache = <String, Future<List<Film>>>{};

  /// [genre] menyaring berdasarkan genre (lihat `genres.dart`) dan dipakai
  /// sebagai label genre film hasilnya.
  static Future<List<Film>> archiveMovies({String? query, Genre? genre, int page = 1}) {
    final key = '${query ?? ''}|${genre?.label ?? ''}|$page';
    return _cache[key] ??= archive
        .fetchMovies(query: query, subject: genre?.archiveSubject, page: page)
        .then((list) => list
            .map((m) => m.toFilm(genres: genre == null ? null : [genre.label, 'Klasik']))
            .toList())
      ..then((_) {}, onError: (_) {
        _cache.remove(key); // jangan simpan kegagalan, supaya bisa dicoba lagi
      });
  }

  /// Lengkapi film Internet Archive dengan link video dan subtitle.
  static Future<Film> archiveDetail(Film film) async {
    final movie = await archive.fetchStreamDetails(ArchiveMovie(
      id: film.archiveId!,
      title: film.title,
      year: film.year == 0 ? null : film.year,
      description: film.synopsis,
    ));
    final full = movie.toFilm();
    // Jumlah unduhan tidak ada di endpoint metadata; pakai kredit dari daftar.
    return Film(
      id: full.id, archiveId: full.archiveId, title: full.title, year: full.year,
      duration: full.duration, genres: film.genres, rating: full.rating,
      quality: full.quality, synopsis: full.synopsis, posterUrl: full.posterUrl,
      videoUrl: full.videoUrl, subtitleUrl: full.subtitleUrl,
      license: full.license, credit: film.credit,
    );
  }
}
