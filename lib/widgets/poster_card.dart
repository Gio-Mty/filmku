import 'package:flutter/material.dart';

import '../models/film.dart';
import '../theme.dart';
import '../screens/navigation.dart';
import 'poster_image.dart';

class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key});
  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 13),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.film, this.width});
  final Film film;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openDetail(context, film),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(film.posterUrl),
                    if (film.rating > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: RatingBadge(film.rating),
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Baris poster yang bisa digeser ke samping.
class PosterRow extends StatelessWidget {
  const PosterRow({super.key, required this.films, this.padding = 16});
  final List<Film> films;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 206,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: films.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => PosterCard(film: films[i], width: 120),
      ),
    );
  }
}

/// Baris poster film yang datanya diambil dari jaringan.
class RemotePosterRow extends StatelessWidget {
  const RemotePosterRow({super.key, required this.load});
  final Future<List<Film>> Function() load;

  @override
  Widget build(BuildContext context) => RemoteRow<Film>(
    load: load,
    builder: (films) => PosterRow(films: films),
  );
}

/// Baris horizontal yang datanya dimuat dari jaringan, lengkap dengan status
/// loading dan pesan gagal + tombol coba lagi.
class RemoteRow<T> extends StatefulWidget {
  const RemoteRow({super.key, required this.load, required this.builder});
  final Future<List<T>> Function() load;
  final Widget Function(List<T> items) builder;

  @override
  State<RemoteRow<T>> createState() => _RemoteRowState<T>();
}

class _RemoteRowState<T> extends State<RemoteRow<T>> {
  late Future<List<T>> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) return widget.builder(snap.data!);
        return SizedBox(
          height: 206,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: snap.hasError
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Gagal memuat: ${snap.error}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _future = widget.load()),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(color: AppColors.accent),
            ),
          ),
        );
      },
    );
  }
}

class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.films});
  final List<Film> films;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.54,
      ),
      itemCount: films.length,
      itemBuilder: (_, i) => PosterCard(film: films[i]),
    );
  }
}
