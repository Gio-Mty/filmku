import '../models/film.dart';

/// Film unggulan utama di Beranda (terkoneksi ke TMDB & pemutar Vidfast).
const featuredFilm = Film(
  id: 'tmdb-1726',
  title: 'Iron Man',
  year: 2008,
  duration: '126 mnt',
  genres: ['Aksi', 'Fiksi Ilmiah', 'Petualangan'],
  rating: 7.7,
  quality: 'HD',
  synopsis:
      'Tony Stark, seorang industrialis miliarder dan penemu jenius yang diculik '
      'dan dipaksa untuk membuat senjata mematikan. Menggunakan kecerdasan dan kepintarannya, '
      'Tony membangun baju zirah berteknologi tinggi dan bersumpah melindungi dunia sebagai Iron Man.',
  posterUrl: 'https://image.tmdb.org/t/p/w500/78lPtwv72eTNqFW9COBYI0dWDJa.jpg',
  videoUrl: null,
  license: 'Vidfast HD',
  credit: 'Data: TMDB | Pemutar: Vidfast',
);

const films = <Film>[featuredFilm];

Film? filmById(String id) {
  if (featuredFilm.id == id) return featuredFilm;
  return null;
}

const allGenres = <String>[
  'Drakor',
  'Drakor On-Going',
  'Drakor Romantis',
  'Drakor Thriller',
  'Aksi',
  'Petualangan',
  'Animasi',
  'Komedi',
  'Drama',
  'Horor',
  'Romantis',
  'Fiksi Ilmiah',
  'Thriller',
  'Fantasi',
  'Misteri',
  'Kriminal',
  'Keluarga',
  'Dokumenter',
  'Perang',
  'Sejarah',
  'Musik',
  'Western',
];

const genreIdMap = <String, String>{
  'Aksi': '28',
  'Petualangan': '12',
  'Animasi': '16',
  'Komedi': '35',
  'Drama': '18',
  'Horor': '27',
  'Romantis': '10749',
  'Fiksi Ilmiah': '878',
  'Thriller': '53',
  'Fantasi': '14',
  'Misteri': '9648',
  'Kriminal': '80',
  'Keluarga': '10751',
  'Dokumenter': '99',
  'Perang': '10752',
  'Sejarah': '36',
  'Musik': '10402',
  'Western': '37',
};

List<Film> filmsInGenre(String genre) =>
    films.where((f) => f.genres.contains(genre)).toList();

List<Film> similarTo(Film film) => const [];
