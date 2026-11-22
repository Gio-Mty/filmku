import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../models/film.dart';
import '../models/series.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/poster_image.dart';
import '../widgets/section_header.dart';
import 'navigation.dart';

/// Detail serial dan daftar episodenya (`GET /api/episodes`).
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key, required this.series});
  final Series series;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late Future<SeriesEpisodes> _future = Backend.episodes(widget.series.slug);

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(series.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<SeriesEpisodes>(
        future: _future,
        builder: (context, snap) {
          final episodes = snap.data?.episodes ?? const <SeriesEpisode>[];
          final films = [for (final e in episodes) e.toFilm(series)];
          // Builder: thumbnail episode baru dibuat saat terlihat.
          return ListenableBuilder(
            listenable: Library.instance,
            builder: (context, _) => ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: 2 + episodes.length,
              itemBuilder: (context, i) {
                if (i == 0) return _Header(series: series);
                if (i == 1) return _status(snap, episodes.length);
                return _EpisodeTile(
                  episode: episodes[i - 2],
                  film: films[i - 2],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _status(AsyncSnapshot<SeriesEpisodes> snap, int count) {
    if (snap.hasError) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gagal memuat episode: ${snap.error}',
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
              onPressed: () => setState(
                () => _future = Backend.episodes(widget.series.slug),
              ),
            ),
          ],
        ),
      );
    }
    if (!snap.hasData) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }
    if (count == 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Belum ada episode.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return SectionHeader('$count Episode');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.series});
  final Series series;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: PosterImage(series.poster),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (series.year != null) '${series.year}',
                        'Internet Archive',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (series.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ExpandableText(series.description),
          ],
        ],
      ),
    );
  }
}

/// Deskripsi Archive bisa sangat panjang; tampilkan beberapa baris dulu.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  static const _collapsedLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(height: 1.5, color: Colors.white70);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Sembunyikan' : 'Selengkapnya'),
              ),
          ],
        );
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.film});
  final SeriesEpisode episode;
  final Film film;

  @override
  Widget build(BuildContext context) {
    final progress = Library.instance.progress(film.id);
    final playable = film.playable;
    final details = [
      film.duration,
      if (!playable) 'Video tidak tersedia',
    ].where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: playable ? () => openPlayer(context, film) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(film.posterUrl),
                      Center(
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.black54,
                          child: Icon(
                            playable
                                ? Icons.play_arrow_rounded
                                : Icons.block_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      if (progress > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: AppColors.accent,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (episode.label.isNotEmpty)
                    Text(
                      episode.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
