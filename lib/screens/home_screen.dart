import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/films.dart';
import '../models/film.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_image.dart';
import '../widgets/section_header.dart';
import '../widgets/update_dialog.dart';
import 'navigation.dart';
import 'search.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) checkAndShowUpdate(context);
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Library.instance,
      builder: (context, _) {
        final history = Library.instance.historyFilms;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _TopBar(),
            _FeaturedCard(film: featuredFilm),
            const SectionHeader('Genre'),
            const _GenreRow(),
            if (history.isNotEmpty) ...[
              const SectionHeader('Lanjutkan Menonton'),
              _ContinueRow(films: history),
            ],
            const SectionHeader('Sedang Tren Minggu Ini'),
            RemotePosterRow(load: Backend.tmdbTrending),
            const SectionHeader('Drakor Sedang Tayang (On-Going)'),
            RemotePosterRow(load: Backend.tmdbKDramaAiring),
            const SectionHeader('Drama Korea (Drakor) Populer'),
            RemotePosterRow(load: Backend.tmdbKDrama),
            const SectionHeader('Drakor Romantis Favorit'),
            RemotePosterRow(load: Backend.tmdbKDramaRomance),
            const SectionHeader('Drakor Misteri & Thriller'),
            RemotePosterRow(load: Backend.tmdbKDramaThriller),
            const SectionHeader('Drakor Rating Tertinggi Sepanjang Masa'),
            RemotePosterRow(load: Backend.tmdbKDramaTopRated),
            const SectionHeader('Film Rating Tertinggi · Pilihan Terbaik'),
            RemotePosterRow(load: Backend.tmdbTopRated),
            const SectionHeader('Film Aksi Populer'),
            RemotePosterRow(
              load: ({int page = 1}) =>
                  Backend.tmdbDiscover(genre: '28', page: page),
            ),
            const SectionHeader('Film Horor & Thriller'),
            RemotePosterRow(
              load: ({int page = 1}) =>
                  Backend.tmdbDiscover(genre: '27', page: page),
            ),
            const SectionHeader('Film Animasi Pilihan'),
            RemotePosterRow(
              load: ({int page = 1}) =>
                  Backend.tmdbDiscover(genre: '16', page: page),
            ),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        children: [
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'f',
                  style: TextStyle(color: AppColors.accent),
                ),
                TextSpan(text: 'ilmku'),
              ],
            ),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Cek Pembaruan',
            icon: const Icon(Icons.system_update_alt_rounded, size: 22),
            onPressed: () => checkAndShowUpdate(context, manual: true),
          ),
          IconButton(
            tooltip: 'Cari',
            icon: const Icon(Icons.search_rounded, size: 26),
            onPressed: () => openSearch(context),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({this.film = featuredFilm});
  final Film film;

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final saved = lib.isSaved(film.id);
    final resume = lib.progress(film.id) > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => openDetail(context, film),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 1.1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'poster-${film.id}',
                      child: PosterImage(film.posterUrl),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.45, 1],
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: Column(
                        children: [
                          Text(
                            film.title.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            film.genres.join('   •   '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    resume ? 'Lanjutkan' : 'Putar',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => openPlayer(context, film),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(saved ? Icons.check_rounded : Icons.add_rounded),
                  label: const Text('Daftarku'),
                  onPressed: () => lib.toggleSaved(film),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GenreRow extends StatelessWidget {
  const _GenreRow();

  @override
  Widget build(BuildContext context) {
    final genres = allGenres;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: genres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final genre = genres[i];
          return GestureDetector(
            onTap: () => openGenre(context, genre),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                genre,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContinueRow extends StatelessWidget {
  const _ContinueRow({required this.films});
  final List<Film> films;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: films.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final film = films[i];
          return SizedBox(
            width: 200,
            child: InkWell(
              onTap: () => openPlayer(context, film),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PosterImage(film.posterUrl),
                          const Center(
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: Library.instance.progress(film.id),
                              minHeight: 3,
                              color: AppColors.accent,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    film.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
