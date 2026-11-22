enum VideoServer {
  vidfast('VidFast (HD)', 'Server Utama Cepat (Subtitle ID)'),
  vidlink('VidLink (No Ads)', 'Server Alternatif 1 (Sangat Bersih & Cepat)'),
  vidsrc('VidSrc (Baru)', 'Server Alternatif 2 (vidsrc.xyz Aktif)'),
  twoembed('2Embed', 'Server Alternatif 3 (Cadangan)'),
  superembed('MultiEmbed', 'Server Alternatif 4 (Cadangan)');

  final String label;
  final String description;
  const VideoServer(this.label, this.description);
}

class Film {
  final String id;
  final String title;
  final int year;
  final String duration;
  final List<String> genres;
  final double rating;
  final String quality;
  final String synopsis;
  final String posterUrl;

  /// Null untuk film Internet Archive sampai detailnya dibuka (lihat [archiveId]).
  final String? videoUrl;
  final String license;
  final String credit;

  /// `identifier` Internet Archive; video dan subtitle diambil saat detail dibuka.
  final String? archiveId;
  final String? subtitleUrl;

  /// Slug serial di backend filmku; terisi untuk episode serial.
  final String? seriesSlug;

  /// ID Serial TV / Drakor di TMDB
  final int? tvId;
  final int? seasonNumber;
  final int? episodeNumber;

  const Film({
    required this.id,
    required this.title,
    required this.year,
    required this.duration,
    required this.genres,
    required this.rating,
    required this.quality,
    required this.synopsis,
    required this.posterUrl,
    required this.videoUrl,
    required this.license,
    required this.credit,
    this.archiveId,
    this.subtitleUrl,
    this.seriesSlug,
    this.tvId,
    this.seasonNumber,
    this.episodeNumber,
  });

  Film copyWith({
    String? id,
    String? title,
    int? year,
    String? duration,
    List<String>? genres,
    double? rating,
    String? quality,
    String? synopsis,
    String? posterUrl,
    String? videoUrl,
    String? license,
    String? credit,
    String? archiveId,
    String? subtitleUrl,
    String? seriesSlug,
    int? tvId,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    return Film(
      id: id ?? this.id,
      title: title ?? this.title,
      year: year ?? this.year,
      duration: duration ?? this.duration,
      genres: genres ?? this.genres,
      rating: rating ?? this.rating,
      quality: quality ?? this.quality,
      synopsis: synopsis ?? this.synopsis,
      posterUrl: posterUrl ?? this.posterUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      license: license ?? this.license,
      credit: credit ?? this.credit,
      archiveId: archiveId ?? this.archiveId,
      subtitleUrl: subtitleUrl ?? this.subtitleUrl,
      seriesSlug: seriesSlug ?? this.seriesSlug,
      tvId: tvId ?? this.tvId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
    );
  }

  bool get playable => videoUrl != null || embedUrl != null;

  bool get isTv =>
      tvId != null ||
      id.startsWith('tmdb-tv-') ||
      seriesSlug != null ||
      (seasonNumber != null && episodeNumber != null);

  int? get parsedTvId {
    if (tvId != null) return tvId;
    if (id.startsWith('tmdb-tv-')) {
      final part = id.substring(8);
      final dashIdx = part.indexOf('-');
      final numStr = dashIdx != -1 ? part.substring(0, dashIdx) : part;
      return int.tryParse(numStr);
    }
    return null;
  }

  /// URL pemutar iframe/embed pihak ketiga berdasarkan server yang dipilih.
  String? embedUrlForServer(VideoServer server) {
    final tid = parsedTvId;
    if (tid != null) {
      final s = seasonNumber ?? 1;
      final ep = episodeNumber ?? 1;
      switch (server) {
        case VideoServer.vidfast:
          return 'https://vidfast.vc/tv/$tid/$s/$ep?nextButton=true&autoNext=true&theme=00D97E&sub=id';
        case VideoServer.vidlink:
          return 'https://vidlink.pro/tv/$tid/$s/$ep?primaryColor=00D97E';
        case VideoServer.vidsrc:
          return 'https://vidsrc.xyz/embed/tv/$tid/$s/$ep';
        case VideoServer.twoembed:
          return 'https://www.2embed.cc/embedtv/$tid&s=$s&e=$ep';
        case VideoServer.superembed:
          return 'https://multiembed.mov/?video_id=$tid&tmdb=1&s=$s&e=$ep';
      }
    }
    final mid = tmdbId;
    if (mid != null) {
      switch (server) {
        case VideoServer.vidfast:
          return 'https://vidfast.vc/movie/$mid?theme=00D97E';
        case VideoServer.vidlink:
          return 'https://vidlink.pro/movie/$mid?primaryColor=00D97E';
        case VideoServer.vidsrc:
          return 'https://vidsrc.xyz/embed/movie/$mid';
        case VideoServer.twoembed:
          return 'https://www.2embed.cc/embed/$mid';
        case VideoServer.superembed:
          return 'https://multiembed.mov/?video_id=$mid&tmdb=1';
      }
    }
    return null;
  }

  /// URL pemutar bawaan (VidFast).
  String? get embedUrl => embedUrlForServer(VideoServer.vidfast);

  /// Film remote; bukan dari data lokal di films.dart, jadi datanya ikut disimpan di Daftarku dan riwayat.
  bool get isRemote =>
      archiveId != null || seriesSlug != null || tmdbId != null || isTv;

  /// ID TMDB untuk film dari backend TMDB (id berbentuk `tmdb-<angka>`, bukan `tmdb-tv-`).
  int? get tmdbId {
    if (id.startsWith('tmdb-tv-')) return null;
    return id.startsWith('tmdb-') ? int.tryParse(id.substring(5)) : null;
  }

  /// Untuk menyimpan film remote di Daftarku dan riwayat.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'year': year,
    'duration': duration,
    'genres': genres,
    'rating': rating,
    'quality': quality,
    'synopsis': synopsis,
    'posterUrl': posterUrl,
    'videoUrl': videoUrl,
    'archiveId': archiveId,
    'subtitleUrl': subtitleUrl,
    'seriesSlug': seriesSlug,
    'license': license,
    'credit': credit,
    'tvId': tvId,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
  };

  factory Film.fromJson(Map<String, dynamic> j) => Film(
    id: j['id'] as String,
    title: j['title'] as String,
    year: (j['year'] as int?) ?? 0,
    duration: (j['duration'] as String?) ?? '',
    genres: List<String>.from(j['genres'] as List? ?? const []),
    rating: (j['rating'] as num?)?.toDouble() ?? 0.0,
    quality: (j['quality'] as String?) ?? '',
    synopsis: (j['synopsis'] as String?) ?? '',
    posterUrl: (j['posterUrl'] as String?) ?? '',
    videoUrl: j['videoUrl'] as String?,
    archiveId: j['archiveId'] as String?,
    subtitleUrl: j['subtitleUrl'] as String?,
    seriesSlug: j['seriesSlug'] as String?,
    license: (j['license'] as String?) ?? '',
    credit: (j['credit'] as String?) ?? '',
    tvId: j['tvId'] as int?,
    seasonNumber: j['seasonNumber'] as int?,
    episodeNumber: j['episodeNumber'] as int?,
  );
}
