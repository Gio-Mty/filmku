import 'package:flutter/material.dart';

import '../state/library.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_header.dart';

class MyListScreen extends StatelessWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Library.instance,
      builder: (context, _) {
        final list = Library.instance.savedFilms;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PageTitle('Daftarku'),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    message: 'Belum ada film tersimpan.\n'
                        'Tekan "Simpan" di halaman film untuk menambahkannya.',
                  )
                : PosterGrid(films: list),
          ),
        ]);
      },
    );
  }
}
