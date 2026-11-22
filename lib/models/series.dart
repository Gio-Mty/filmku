import 'film.dart';

/// Serial dari backend filmku (`GET /api/catalog`).
class Series {
  final String slug;
  final String title;
  final int? year;
  final String description;
  final String poster;
  final int downloads;

  const Series({
    required this.slug,
    required this.title,
    this.year,
    this.description = '',
    required this.poster,
    this.downloads = 0,
  });

  factory Series.fromJson(Map<String, dynamic> j) => Series(
    slug: j['slug'] as String,
    title: j['title'] as String? ?? j['slug'] as String,
    year: j['year'] as int?,
    description: j['description'] as String? ?? '',
    poster: j['poster'] as String? ?? '',
    downloads: j['downloads'] as int? ?? 0,
  );
}

/// Satu episode dari `GET /api/episodes`; backend sudah mengurutkannya.
class SeriesEpisode {
  final int? season;
  final int? episode;
  final String title;
  final int? duration; // detik
  final String? thumbnail;
  final String? streamUrl;
  final String? subtitleUrl;

  const SeriesEpisode({
    this.season,
    this.episode,
    required this.title,
    this.duration,
    this.thumbnail,
    this.streamUrl,
    this.subtitleUrl,
  });

  factory SeriesEpisode.fromJson(Map<String, dynamic> j) => SeriesEpisode(
    season: j['season'] as int?,
    episode: j['episode'] as int?,
    title: j['title'] as String? ?? '',
    duration: j['duration'] as int?,
    thumbnail: j['thumbnail'] as String?,
    streamUrl: j['stream_url'] as String?,
    subtitleUrl: j['subtitle_url'] as String?,
  );

  /// "S1 · E19", "Episode 3", atau kosong jika nomornya tidak diketahui.
  String get label {
    if (episode == null) return '';
    return season == null ? 'Episode $episode' : 'S$season · E$episode';
  }

  /// Sebagai [Film] supaya bisa memakai pemutar, riwayat, dan Daftarku yang sama.
  /// Id memakai judul episode, yang diambil dari nama file di Archive dan tidak berubah.
  Film toFilm(Series series) => Film(
    id: 'ep:${series.slug}/$title',
    seriesSlug: series.slug,
    title: title,
    year: series.year ?? 0,
    duration: duration == null ? '' : '${(duration! / 60).ceil()} mnt',
    genres: const ['Serial'],
    rating: 0,
    quality: '',
    synopsis: series.description,
    posterUrl: thumbnail ?? series.poster,
    videoUrl: streamUrl,
    subtitleUrl: subtitleUrl,
    license: 'ARCHIVE',
    credit: 'Internet Archive · ${series.title}',
  );
}

class SeriesEpisodes {
  final Series series;
  final List<SeriesEpisode> episodes;

  const SeriesEpisodes({required this.series, required this.episodes});

  factory SeriesEpisodes.fromJson(Map<String, dynamic> j) => SeriesEpisodes(
    series: Series.fromJson(j['series'] as Map<String, dynamic>),
    episodes: (j['episodes'] as List)
        .map((e) => SeriesEpisode.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
