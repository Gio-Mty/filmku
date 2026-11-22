import 'dart:convert';

import 'package:filmku/data/backend.dart';
import 'package:filmku/models/film.dart';
import 'package:filmku/models/tmdb_detail.dart';
import 'package:filmku/state/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bentuk sama dengan respons backend GET /api/tmdb/movie/1022789.
const _detailJson = {
  'id': 1022789,
  'title': 'Inside Out 2',
  'year': 2024,
  'overview': 'Riley kini remaja.',
  'poster': 'https://image.tmdb.org/t/p/w500/poster.jpg',
  'backdrop': null,
  'rating': 7.6,
  'genres': ['Animasi', 'Keluarga'],
  'cast': [
    {
      'name': 'Amy Poehler',
      'character': 'Joy (voice)',
      'photo': 'https://image.tmdb.org/t/p/w185/a.jpg',
    },
    {'name': 'Pemeran', 'character': '', 'photo': null},
  ],
  'trailer': {
    'name': 'Official Trailer',
    'url': 'https://www.youtube.com/watch?v=LEjhY15eCx0',
    'thumbnail': 'https://i.ytimg.com/vi/LEjhY15eCx0/hqdefault.jpg',
  },
  'providers': [
    {
      'name': 'Disney+',
      'logo': 'https://image.tmdb.org/t/p/w92/d.png',
      'kind': 'flatrate',
    },
    {'name': 'Apple TV Store', 'logo': null, 'kind': 'rent'},
    {
      'name': 'Google Play Movies',
      'logo': 'https://image.tmdb.org/t/p/w92/g.png',
      'kind': 'rent',
    },
    {'name': 'Apple TV Store', 'logo': null, 'kind': 'buy'},
  ],
  'watch_link':
      'https://www.themoviedb.org/movie/1022789-inside-out-2/watch?locale=ID',
};

Film _film(String id) => Film(
  id: id,
  title: 'Film',
  year: 0,
  duration: '',
  genres: const [],
  rating: 0,
  quality: '',
  synopsis: '',
  posterUrl: '',
  videoUrl: null,
  license: '',
  credit: '',
);

void main() {
  test(
    'detail TMDB diambil dari backend, penyedia dikelompokkan per jenis',
    () async {
      final requested = <Uri>[];
      final detail = await http.runWithClient(
        () => Backend.tmdbDetail(1022789),
        () => MockClient((request) async {
          requested.add(request.url);
          return http.Response(jsonEncode(_detailJson), 200);
        }),
      );

      expect(requested.single.path, '/api/tmdb/movie/1022789');
      expect(
        detail.trailer!.url,
        'https://www.youtube.com/watch?v=LEjhY15eCx0',
      );
      expect(
        [for (final c in detail.cast) (c.name, c.character, c.photo)],
        [
          (
            'Amy Poehler',
            'Joy (voice)',
            'https://image.tmdb.org/t/p/w185/a.jpg',
          ),
          ('Pemeran', '', null),
        ],
      );
      expect(detail.providersByKind.keys, ['flatrate', 'rent', 'buy']);
      expect(
        [for (final p in detail.providersByKind['rent']!) (p.name, p.logo)],
        [
          ('Apple TV Store', null),
          ('Google Play Movies', 'https://image.tmdb.org/t/p/w92/g.png'),
        ],
      );
      expect(
        detail.watchLink,
        'https://www.themoviedb.org/movie/1022789-inside-out-2/watch?locale=ID',
      );
    },
  );

  test('film tanpa trailer dan belum ada di layanan Indonesia', () {
    final detail = TmdbDetail.fromJson({
      ..._detailJson,
      'cast': <Object>[],
      'trailer': null,
      'providers': <Object>[],
      'watch_link': null,
    });
    expect(detail.cast, isEmpty);
    expect(detail.trailer, isNull);
    expect(detail.providersByKind, isEmpty);
    expect(detail.watchLink, isNull);
  });

  test('film TMDB yang disimpan muncul di Daftarku', () async {
    SharedPreferences.setMockInitialValues({});
    await Library.instance.load();

    Library.instance.toggleSaved(_film('tmdb-1022789'));

    expect(
      [for (final f in Library.instance.savedFilms) f.id],
      ['tmdb-1022789'],
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remote_films'), contains('tmdb-1022789'));
  });

  test('id TMDB dibaca dari id film', () {
    expect(_film('tmdb-1022789').tmdbId, 1022789);
    expect(_film('tmdb-abc').tmdbId, isNull);
    expect(_film('ia-night_of_the_living_dead').tmdbId, isNull);
    expect(_film('bbb').tmdbId, isNull);
  });
}
