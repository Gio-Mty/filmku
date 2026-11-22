import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/backend.dart';
import '../models/film.dart';
import '../models/tmdb_detail.dart';
import '../models/tv_detail.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_image.dart';
import '../widgets/tmdb_sections.dart';
import 'navigation.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.film});
  final Film film;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  int _tab = 0;
  late Film _film = widget.film;
  bool _loadingStream = false;
  String? _streamError;
  bool _streamFailed = false; // gagal jaringan, bisa dicoba lagi

  /// Pemain, trailer, dan layanan resmi; hanya untuk film dari TMDB.
  Future<TmdbDetail>? _tmdb;

  /// Detail TV / Drakor (musim dan daftar episode).
  Future<TvDetail>? _tvDetail;
  Future<List<TvEpisode>>? _episodes;
  int _selectedSeason = 1;

  @override
  void initState() {
    super.initState();
    if (widget.film.isTv && widget.film.parsedTvId != null) {
      _loadTv(widget.film.parsedTvId!, widget.film.seasonNumber ?? 1);
    } else {
      // Link video Internet Archive diambil saat detail dibuka, bukan saat daftar dimuat.
      if (widget.film.archiveId != null && !widget.film.playable) _loadStream();
      final tmdbId = widget.film.tmdbId;
      if (tmdbId != null) _tmdb = Backend.tmdbDetail(tmdbId);
    }
  }

  void _loadTv(int tvId, int season) {
    setState(() {
      _selectedSeason = season;
      _tvDetail = Backend.tmdbTvDetail(tvId);
      _episodes = Backend.tmdbTvSeason(tvId, season);
    });
  }

  void _changeSeason(int season) {
    setState(() {
      _selectedSeason = season;
      _episodes = Backend.tmdbTvSeason(widget.film.parsedTvId!, season);
    });
  }

  void _reloadTmdb() {
    setState(() => _tmdb = Backend.tmdbDetail(widget.film.tmdbId!));
  }

  void _loadStream() {
    setState(() {
      _loadingStream = true;
      _streamError = null;
      _streamFailed = false;
    });
    Api.archiveDetail(widget.film).then(
      (f) {
        if (!mounted) return;
        setState(() {
          _film = f;
          _loadingStream = false;
          if (!f.playable) {
            _streamError = 'Video tidak tersedia untuk film ini.';
          }
        });
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _loadingStream = false;
            _streamFailed = true;
            _streamError = 'Gagal memuat. Ketuk untuk coba lagi';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final film = _film;
    final lib = Library.instance;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListenableBuilder(
        listenable: lib,
        builder: (context, _) => ListView(
          padding: EdgeInsets.zero,
          children: [
            _Backdrop(film: film),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          film.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (film.license.isNotEmpty) _Badge(film.license),
                    ],
                  ),
                  if (film.isTv && _tvDetail != null)
                    FutureBuilder<TvDetail>(
                      future: _tvDetail,
                      builder: (context, snap) {
                        final tv = snap.data;
                        if (tv == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (tv.status.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: tv.status.contains('On-Going')
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : Colors.blueGrey
                                            .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: tv.status.contains('On-Going')
                                          ? Colors.greenAccent
                                          : Colors.white24,
                                    ),
                                  ),
                                  child: Text(
                                    tv.status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: tv.status.contains('On-Going')
                                          ? Colors.greenAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              for (final net in tv.networks)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    net,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white),
                                  ),
                                ),
                              if (tv.nextEpisode != null)
                                Text(
                                  'Jadwal tayang: ${tv.nextEpisode}',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.muted),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (film.rating > 0) _RatingChip(film.rating),
                      if (film.year > 0) _Chip('${film.year}'),
                      if (film.duration.isNotEmpty)
                        _Chip(film.duration, filled: true),
                      if (film.quality.isNotEmpty)
                        _Chip(film.quality, outlined: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    film.genres.join(', '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    film.synopsis,
                    style: const TextStyle(height: 1.5, color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: film.playable
                            ? _PlayButton(film: film)
                            : _tmdb != null
                            ? _TrailerButton(
                                detail: _tmdb!,
                                onRetry: _reloadTmdb,
                              )
                            : _StatusButton(
                                loading: _loadingStream,
                                label: _loadingStream
                                    ? 'Menyiapkan video…'
                                    : _streamError ?? '',
                                icon: _streamFailed
                                    ? Icons.refresh_rounded
                                    : Icons.block_rounded,
                                onPressed: _streamFailed ? _loadStream : null,
                              ),
                      ),
                      const SizedBox(width: 10),
                      _SaveButton(
                        saved: lib.isSaved(film.id),
                        onTap: () => lib.toggleSaved(film),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_tmdb != null) TmdbSections(detail: _tmdb!),
            if (film.isTv && _tvDetail != null)
              TvProvidersSection(detail: _tvDetail!),
            Builder(
              builder: (context) {
                final isTv = film.isTv;
                final labels = isTv
                    ? const ['EPISODE', 'LAINNYA', 'DETAIL']
                    : const ['LAINNYA', 'DETAIL'];
                final activeTab = _tab < labels.length ? _tab : 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                      child: _Tabs(
                        labels: labels,
                        index: activeTab,
                        onChanged: (i) => setState(() => _tab = i),
                      ),
                    ),
                    if (isTv) ...[
                      if (activeTab == 0)
                        _TvEpisodesSection(
                          film: film,
                          tvDetail: _tvDetail,
                          episodes: _episodes,
                          selectedSeason: _selectedSeason,
                          onSelectSeason: _changeSeason,
                        )
                      else if (activeTab == 1)
                        RemotePosterRow(load: Backend.tmdbKDrama)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _TvInfoTable(
                            film: film,
                            tvDetail: _tvDetail,
                          ),
                        ),
                    ] else ...[
                      if (activeTab == 0)
                        RemotePosterRow(load: Backend.tmdbPopular)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _InfoTable(film: film),
                        ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.film});
  final Film film;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 0.95,
          child: Hero(
            tag: 'poster-${film.id}',
            child: PosterImage(film.posterUrl),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.5, 1],
                colors: [Colors.transparent, AppColors.bg],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.accent),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip(this.rating);
  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.filled = false, this.outlined = false});
  final String text;
  final bool filled;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? Colors.white12 : null,
        border: outlined ? Border.all(color: Colors.white38) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.film});
  final Film film;

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final progress = lib.progress(film.id);
    final resume = progress > 0;

    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openPlayer(context, film),
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  size: 30,
                  color: AppColors.onAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resume
                            ? 'Lanjutkan ${formatPosition(lib.position(film.id))}'
                            : (film.isTv ? 'Putar Episode 1' : 'Putar'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onAccent,
                        ),
                      ),
                      if (resume) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: AppColors.onAccent,
                            backgroundColor: AppColors.onAccent.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol utama saat film belum bisa langsung diputar: video Internet Archive
/// yang sedang disiapkan, atau trailer film TMDB.
class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    this.icon = Icons.block_rounded,
    this.loading = false,
    this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.surface,
          disabledForegroundColor: AppColors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onPressed: onPressed,
      ),
    );
  }
}

/// Film TMDB tidak bisa diputar di filmku, jadi tombol utamanya membuka
/// trailer resmi di YouTube.
class _TrailerButton extends StatelessWidget {
  const _TrailerButton({required this.detail, required this.onRetry});
  final Future<TmdbDetail> detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TmdbDetail>(
      future: detail,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _StatusButton(label: 'Memuat trailer…', loading: true);
        }
        if (snap.hasError) {
          return _StatusButton(
            label: 'Gagal memuat. Ketuk untuk coba lagi',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          );
        }
        final trailer = snap.data!.trailer;
        if (trailer == null) {
          return const _StatusButton(label: 'Trailer tidak tersedia');
        }
        return _StatusButton(
          label: 'Tonton Trailer',
          icon: Icons.play_arrow_rounded,
          onPressed: () => openLink(context, trailer.url),
        );
      },
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap});
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = saved ? AppColors.accent : Colors.white;
    return Material(
      color: saved
          ? AppColors.accent.withValues(alpha: 0.12)
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: saved ? AppColors.accent : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  saved ? Icons.check_rounded : Icons.add_rounded,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  saved ? 'Tersimpan' : 'Simpan',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: InkWell(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == index
                            ? AppColors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: i == index ? Colors.white : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.film});
  final Film film;

  @override
  Widget build(BuildContext context) {
    final rows = {
      if (film.year > 0) 'Tahun': '${film.year}',
      'Durasi': film.duration,
      'Genre': film.genres.join(', '),
      'Kualitas': film.quality,
      'Lisensi': film.license,
      'Kredit': film.credit,
    };
    return Column(
      children: [
        for (final e in rows.entries.where((e) => e.value.isNotEmpty))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    e.key,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                Expanded(child: Text(e.value)),
              ],
            ),
          ),
      ],
    );
  }
}

class _TvEpisodesSection extends StatelessWidget {
  const _TvEpisodesSection({
    required this.film,
    required this.tvDetail,
    required this.episodes,
    required this.selectedSeason,
    required this.onSelectSeason,
  });

  final Film film;
  final Future<TvDetail>? tvDetail;
  final Future<List<TvEpisode>>? episodes;
  final int selectedSeason;
  final ValueChanged<int> onSelectSeason;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tvDetail != null)
          FutureBuilder<TvDetail>(
            future: tvDetail,
            builder: (context, snap) {
              final seasons = snap.data?.seasons ?? const [];
              if (seasons.length <= 1) return const SizedBox.shrink();
              return SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final s = seasons[i];
                    final isSelected = s.seasonNumber == selectedSeason;
                    return ChoiceChip(
                      label: Text(s.name),
                      selected: isSelected,
                      onSelected: (_) => onSelectSeason(s.seasonNumber),
                      selectedColor: AppColors.accent,
                      backgroundColor: AppColors.surface,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.onAccent : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        if (episodes != null)
          FutureBuilder<List<TvEpisode>>(
            future: episodes,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                );
              }
              if (snap.hasError) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Gagal memuat episode.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                );
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Episode belum tersedia.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(
                  color: Colors.white12,
                  height: 20,
                ),
                itemBuilder: (context, i) {
                  final ep = list[i];
                  final epFilm = Film(
                    id: 'tmdb-tv-${film.parsedTvId}-s$selectedSeason-e${ep.episodeNumber}',
                    title: '${film.title} - S$selectedSeason:E${ep.episodeNumber} ${ep.name}',
                    year: film.year,
                    duration: '',
                    genres: film.genres,
                    rating: ep.rating > 0 ? ep.rating : film.rating,
                    quality: 'HD',
                    synopsis: ep.overview.isNotEmpty ? ep.overview : film.synopsis,
                    posterUrl: ep.still ?? film.posterUrl,
                    videoUrl: null,
                    license: 'Vidfast HD',
                    credit: 'Data: TMDB | Pemutar: Vidfast',
                    tvId: film.parsedTvId,
                    seasonNumber: selectedSeason,
                    episodeNumber: ep.episodeNumber,
                  );

                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => openPlayer(context, epFilm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 120,
                              height: 68,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  PosterImage(ep.still ?? film.posterUrl),
                                  const Center(
                                    child: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.black54,
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Episode ${ep.episodeNumber}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ep.name.isNotEmpty
                                      ? ep.name
                                      : 'Episode ${ep.episodeNumber}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                if (ep.overview.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    ep.overview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white60,
                                      height: 1.3,
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
                },
              );
            },
          ),
      ],
    );
  }
}

class _TvInfoTable extends StatelessWidget {
  const _TvInfoTable({required this.film, this.tvDetail});
  final Film film;
  final Future<TvDetail>? tvDetail;

  @override
  Widget build(BuildContext context) {
    if (tvDetail == null) return _InfoTable(film: film);

    return FutureBuilder<TvDetail>(
      future: tvDetail,
      builder: (context, snap) {
        final d = snap.data;
        final rows = {
          if (film.year > 0) 'Tahun': '${film.year}',
          if (d != null && d.status.isNotEmpty) 'Status': d.status,
          if (d != null && d.networks.isNotEmpty)
            'Jaringan': d.networks.join(', '),
          if (d != null && d.nextEpisode != null)
            'Tayang Selanjutnya': d.nextEpisode!,
          if (d != null) 'Total Musim': '${d.numberOfSeasons} Musim',
          if (d != null) 'Total Episode': '${d.numberOfEpisodes} Episode',
          'Genre': film.genres.join(', '),
          'Kualitas': film.quality.isNotEmpty ? film.quality : 'HD',
          'Lisensi': film.license,
          'Kredit': film.credit,
        };
        return Column(
          children: [
            for (final e in rows.entries.where((e) => e.value.isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        e.key,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                    Expanded(child: Text(e.value)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
