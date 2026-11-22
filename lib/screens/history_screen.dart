import 'package:flutter/material.dart';

import '../state/library.dart';
import '../theme.dart';
import '../widgets/poster_image.dart';
import '../widgets/section_header.dart';
import 'navigation.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final list = lib.historyFilms;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageTitle(
            'Riwayat',
            action: list.isEmpty
                ? null
                : TextButton(onPressed: lib.clearHistory, child: const Text('Hapus')),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.history_rounded,
                    message: 'Film yang kamu tonton akan muncul di sini.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final film = list[i];
                      final progress = lib.progress(film.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => openDetail(context, film),
                        child: Row(children: [
                          SizedBox(
                            width: 140,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Stack(fit: StackFit.expand, children: [
                                  PosterImage(film.posterUrl),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: LinearProgressIndicator(
                                      value: progress > 0 ? progress : 1,
                                      minHeight: 3,
                                      color: AppColors.accent,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(film.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(
                                  progress > 0
                                      ? 'Berhenti di ${formatPosition(lib.position(film.id))}'
                                      : 'Selesai ditonton',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}
