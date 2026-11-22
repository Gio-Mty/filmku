import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../models/film.dart';
import '../theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_header.dart';

void openSearch(BuildContext context) =>
    showSearch<void>(context: context, delegate: FilmSearch());

class FilmSearch extends SearchDelegate<void> {
  FilmSearch() : super(searchFieldLabel: 'Cari judul film');

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(backgroundColor: AppColors.bg),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Hapus',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) {
    final q = query.trim();
    if (q.length < 2) return _grid(const []);
    return FutureBuilder<List<Film>>(
      future: Backend.tmdbSearch(q),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: AppColors.bg,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        return _grid(snap.data ?? const []);
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.trim();
    if (q.length < 2) {
      return const ColoredBox(
        color: AppColors.bg,
        child: Center(
          child: Text(
            'Ketik judul film untuk mencari di TMDB...',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }
    return FutureBuilder<List<Film>>(
      future: Backend.tmdbSearch(q),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: AppColors.bg,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        return _grid(snap.data ?? const []);
      },
    );
  }

  Widget _grid(List<Film> list) {
    return ColoredBox(
      color: AppColors.bg,
      child: list.isEmpty
          ? const EmptyState(
              icon: Icons.search_off_rounded,
              message: 'Film tidak ditemukan.',
            )
          : PosterGrid(films: list),
    );
  }
}
