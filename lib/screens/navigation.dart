import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/film.dart';
import '../models/series.dart';
import '../state/library.dart';
import 'detail_screen.dart';
import 'embed_player_screen.dart';
import 'genre_screen.dart';
import 'player_screen.dart';
import 'series_screen.dart';

void openDetail(BuildContext context, Film film) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => DetailScreen(film: film)),
);

void openPlayer(BuildContext context, Film film) {
  Library.instance.remember(film);
  if (film.embedUrl != null) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EmbedPlayerScreen(film: film)),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PlayerScreen(film: film)),
  );
}

void openSeries(BuildContext context, Series series) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => SeriesScreen(series: series)),
);

void openGenre(BuildContext context, String genre) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => GenreScreen(genre: genre)),
);

/// Membuka [url] di luar app (aplikasi YouTube atau browser); di web, tab baru.
Future<void> openLink(BuildContext context, String url) async {
  bool opened;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } on Exception {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Tautan tidak bisa dibuka')));
  }
}

String formatPosition(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
