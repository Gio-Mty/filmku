import 'tmdb_detail.dart';

class TvSeasonInfo {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? poster;

  const TvSeasonInfo({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.poster,
  });

  factory TvSeasonInfo.fromJson(Map<String, dynamic> j) => TvSeasonInfo(
        seasonNumber: (j['season_number'] as num?)?.toInt() ?? 1,
        name: (j['name'] as String?) ?? 'Season 1',
        episodeCount: (j['episode_count'] as num?)?.toInt() ?? 0,
        poster: j['poster'] as String?,
      );
}

class TvEpisode {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? still;
  final double rating;
  final String? airDate;

  const TvEpisode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    this.still,
    required this.rating,
    this.airDate,
  });

  factory TvEpisode.fromJson(Map<String, dynamic> j) => TvEpisode(
        id: (j['id'] as num?)?.toInt() ?? 0,
        episodeNumber: (j['episode_number'] as num?)?.toInt() ?? 1,
        seasonNumber: (j['season_number'] as num?)?.toInt() ?? 1,
        name: (j['name'] as String?) ?? '',
        overview: (j['overview'] as String?) ?? '',
        still: j['still'] as String?,
        rating: (j['rating'] as num?)?.toDouble() ?? 0.0,
        airDate: j['air_date'] as String?,
      );
}

class TvDetail {
  final int id;
  final String title;
  final int year;
  final String overview;
  final String? poster;
  final String? backdrop;
  final double rating;
  final List<String> genres;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final List<TvSeasonInfo> seasons;
  final String status;
  final List<String> networks;
  final String? nextEpisode;
  final List<WatchProvider> providers;
  final String? watchLink;

  const TvDetail({
    required this.id,
    required this.title,
    required this.year,
    required this.overview,
    this.poster,
    this.backdrop,
    required this.rating,
    required this.genres,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.seasons,
    this.status = '',
    this.networks = const [],
    this.nextEpisode,
    this.providers = const [],
    this.watchLink,
  });

  factory TvDetail.fromJson(Map<String, dynamic> j) => TvDetail(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        year: (j['year'] as num?)?.toInt() ?? 0,
        overview: (j['overview'] as String?) ?? '',
        poster: j['poster'] as String?,
        backdrop: j['backdrop'] as String?,
        rating: (j['rating'] as num?)?.toDouble() ?? 0.0,
        genres: List<String>.from(j['genres'] as List? ?? const []),
        numberOfSeasons: (j['number_of_seasons'] as num?)?.toInt() ?? 1,
        numberOfEpisodes: (j['number_of_episodes'] as num?)?.toInt() ?? 0,
        seasons: (j['seasons'] as List? ?? const [])
            .map((s) => TvSeasonInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
        status: (j['status'] as String?) ?? '',
        networks: List<String>.from(j['networks'] as List? ?? const []),
        nextEpisode: j['next_episode'] as String?,
        providers: (j['providers'] as List? ?? const [])
            .map((p) => WatchProvider.fromJson(p as Map<String, dynamic>))
            .toList(),
        watchLink: j['watch_link'] as String?,
      );

  Map<String, List<WatchProvider>> get providersByKind {
    final groups = <String, List<WatchProvider>>{};
    for (final p in providers) {
      (groups[p.kind] ??= []).add(p);
    }
    return groups;
  }
}
