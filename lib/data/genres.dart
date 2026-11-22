import 'package:flutter/material.dart';

/// Genre yang bisa dipilih di app.
///
/// [archiveSubject] adalah ekspresi untuk field `subject` di pencarian Internet
/// Archive (sintaks Lucene). Nilainya konstanta di sini, bukan input pengguna.
class Genre {
  const Genre(this.label, this.icon, this.archiveSubject);
  final String label;
  final IconData icon;
  final String archiveSubject;
}

const genres = <Genre>[
  Genre('Aksi', Icons.local_fire_department_rounded, 'action'),
  Genre('Komedi', Icons.sentiment_very_satisfied_rounded, 'comedy'),
  Genre('Drama', Icons.theater_comedy_rounded, 'drama'),
  Genre('Horor', Icons.nightlight_round, 'horror'),
  Genre('Fiksi Ilmiah', Icons.rocket_launch_rounded, '"science fiction" OR "sci-fi"'),
  Genre('Fantasi', Icons.auto_awesome_rounded, 'fantasy'),
  Genre('Animasi', Icons.animation_rounded, 'animation OR cartoon'),
  Genre('Romantis', Icons.favorite_rounded, 'romance'),
  Genre('Kriminal', Icons.local_police_rounded, 'crime OR "film noir"'),
  Genre('Misteri', Icons.search_rounded, 'mystery OR thriller'),
  Genre('Petualangan', Icons.explore_rounded, 'adventure'),
  Genre('Western', Icons.landscape_rounded, 'western'),
  Genre('Perang', Icons.military_tech_rounded, 'war'),
  Genre('Musikal', Icons.music_note_rounded, 'musical'),
  Genre('Dokumenter', Icons.videocam_rounded, 'documentary'),
  Genre('Keluarga', Icons.family_restroom_rounded, 'family'),
];

Genre genreByLabel(String label) =>
    genres.firstWhere((g) => g.label == label, orElse: () => genres.first);
