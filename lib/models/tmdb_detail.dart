/// Info tambahan film TMDB dari backend (`GET /api/tmdb/movie/{id}`).
class TmdbDetail {
  const TmdbDetail({
    required this.cast,
    required this.trailer,
    required this.providers,
    required this.watchLink,
  });

  final List<CastMember> cast;
  final Trailer? trailer;

  /// Layanan streaming resmi di Indonesia, sudah urut per jenis dari backend.
  /// Sumber datanya JustWatch, jadi tampilan wajib menyebut JustWatch.
  final List<WatchProvider> providers;

  /// Halaman TMDB yang menautkan ke setiap layanan.
  final String? watchLink;

  factory TmdbDetail.fromJson(Map<String, dynamic> j) => TmdbDetail(
    cast: [
      for (final c in j['cast'] as List? ?? const [])
        CastMember.fromJson(c as Map<String, dynamic>),
    ],
    trailer: j['trailer'] == null
        ? null
        : Trailer.fromJson(j['trailer'] as Map<String, dynamic>),
    providers: [
      for (final p in j['providers'] as List? ?? const [])
        WatchProvider.fromJson(p as Map<String, dynamic>),
    ],
    watchLink: j['watch_link'] as String?,
  );

  /// Penyedia per jenis (`flatrate`, `free`, `ads`, `rent`, `buy`), urutan jenis
  /// dan urutan di dalamnya mengikuti backend.
  Map<String, List<WatchProvider>> get providersByKind {
    final groups = <String, List<WatchProvider>>{};
    for (final p in providers) {
      (groups[p.kind] ??= []).add(p);
    }
    return groups;
  }
}

class CastMember {
  const CastMember({
    required this.name,
    required this.character,
    required this.photo,
  });

  final String name;
  final String character;
  final String? photo;

  factory CastMember.fromJson(Map<String, dynamic> j) => CastMember(
    name: j['name'] as String,
    character: j['character'] as String? ?? '',
    photo: j['photo'] as String?,
  );
}

class Trailer {
  const Trailer({required this.name, required this.url});

  final String name;

  /// Halaman video di YouTube.
  final String url;

  factory Trailer.fromJson(Map<String, dynamic> j) =>
      Trailer(name: j['name'] as String, url: j['url'] as String);
}

class WatchProvider {
  const WatchProvider({
    required this.name,
    required this.logo,
    required this.kind,
  });

  final String name;
  final String? logo;
  final String kind;

  factory WatchProvider.fromJson(Map<String, dynamic> j) => WatchProvider(
    name: j['name'] as String,
    logo: j['logo'] as String?,
    kind: j['kind'] as String,
  );
}
