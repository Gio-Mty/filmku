import 'package:flutter/material.dart';

import '../models/tmdb_detail.dart';
import '../models/tv_detail.dart';
import '../screens/navigation.dart';
import '../theme.dart';
import 'section_header.dart';

/// Layanan streaming resmi di Indonesia dan daftar pemain untuk film TMDB.
///
/// Status muat dan galat sudah tampil di tombol trailer halaman detail, jadi
/// bagian ini kosong sampai datanya siap.
class TmdbSections extends StatelessWidget {
  const TmdbSections({super.key, required this.detail});
  final Future<TmdbDetail> detail;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TmdbDetail>(
      future: detail,
      builder: (context, snap) {
        final data = snap.connectionState == ConnectionState.done
            ? snap.data
            : null;
        if (data == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WatchProviders(detail: data),
            if (data.cast.isNotEmpty) _CastRow(cast: data.cast),
          ],
        );
      },
    );
  }
}

class TvProvidersSection extends StatelessWidget {
  const TvProvidersSection({super.key, required this.detail});
  final Future<TvDetail> detail;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TvDetail>(
      future: detail,
      builder: (context, snap) {
        final data =
            snap.connectionState == ConnectionState.done ? snap.data : null;
        if (data == null || data.providers.isEmpty) {
          return const SizedBox.shrink();
        }
        final groups = data.providersByKind;
        final link = data.watchLink;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Tersedia Resmi di Indonesia'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final MapEntry(key: kind, value: providers)
                      in groups.entries) ...[
                    Text(
                      _kindLabels[kind] ?? kind,
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in providers)
                          _ProviderChip(
                            provider: p,
                            onTap: link == null
                                ? null
                                : () => openLink(context, link),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  const Text(
                    'Data layanan dari JustWatch',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

const _kindLabels = {
  'flatrate': 'Langganan',
  'free': 'Gratis',
  'ads': 'Gratis dengan iklan',
  'rent': 'Sewa',
  'buy': 'Beli',
};

class _WatchProviders extends StatelessWidget {
  const _WatchProviders({required this.detail});
  final TmdbDetail detail;

  @override
  Widget build(BuildContext context) {
    final groups = detail.providersByKind;
    final link = detail.watchLink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Tersedia di Indonesia'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (groups.isEmpty) ...[
                const Text(
                  'Belum ada di layanan streaming resmi di Indonesia.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 10),
              ],
              for (final MapEntry(key: kind, value: providers)
                  in groups.entries) ...[
                Text(
                  _kindLabels[kind] ?? kind,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in providers)
                      _ProviderChip(
                        provider: p,
                        onTap: link == null
                            ? null
                            : () => openLink(context, link),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              // Syarat TMDB untuk data penyedia: sumbernya harus disebut.
              const Text(
                'Data layanan dari JustWatch',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({required this.provider, required this.onTap});
  final WatchProvider provider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final logo = provider.logo;
    const placeholder = ColoredBox(
      color: Colors.white10,
      child: Icon(Icons.live_tv_rounded, size: 18, color: Colors.white54),
    );
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox.square(
                  dimension: 32,
                  child: logo == null
                      ? placeholder
                      : Image.network(
                          logo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => placeholder,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  provider.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.cast});
  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Daftar Pemain'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [for (final person in cast) _CastCard(person: person)],
          ),
        ),
      ],
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.person});
  final CastMember person;

  @override
  Widget build(BuildContext context) {
    final photo = person.photo;
    final initials = ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Text(
          _initials(person.name),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ),
    );
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: 76,
              child: photo == null
                  ? initials
                  : Image.network(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => initials,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          if (person.character.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              person.character,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _initials(String name) => name
    .split(' ')
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w.characters.first.toUpperCase())
    .join();
