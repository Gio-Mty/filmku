import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../models/series.dart';
import '../screens/navigation.dart';
import 'poster_card.dart';
import 'poster_image.dart';

/// Kartu serial; ukurannya sama dengan [PosterCard] supaya baris di Beranda seragam.
class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, required this.series, this.width});
  final Series series;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openSeries(context, series),
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
                    PosterImage(series.poster),
                    if (series.year != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${series.year}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              series.title,
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

/// Baris serial dari backend filmku (`GET /api/catalog`).
class RemoteSeriesRow extends StatelessWidget {
  const RemoteSeriesRow({super.key});

  @override
  Widget build(BuildContext context) {
    return RemoteRow<Series>(
      load: Backend.catalog,
      builder: (list) => SizedBox(
        height: 206,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SeriesCard(series: list[i], width: 120),
        ),
      ),
    );
  }
}
