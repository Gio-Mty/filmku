import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/subtitles.dart';
import '../data/video_quality.dart';
import '../models/film.dart';
import '../state/library.dart';
import '../theme.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.film});
  final Film film;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _video;
  ChewieController? _chewie;
  String? _error;

  /// Kualitas terakhir yang dipilih, dipakai lagi untuk film berikutnya.
  static String _lastQuality = defaultQuality;
  late final List<String> _qualities = qualitiesFor(widget.film.videoUrl!);
  late String _quality =
      _qualities.contains(_lastQuality) ? _lastQuality : defaultQuality;

  // Diunduh sekali, dipakai lagi saat kualitas diganti.
  late final Future<List<Subtitle>> _subtitles = widget.film.subtitleUrl == null
      ? Future.value(const [])
      : loadSubtitles(widget.film.subtitleUrl!);

  @override
  void initState() {
    super.initState();
    _load(start: Library.instance.position(widget.film.id));
  }

  void _load({required Duration start, double speed = 1.0}) {
    final source = widget.film.videoUrl!;
    final url = _qualities.isEmpty ? source : urlForQuality(source, _quality);
    final video = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = video;
    Future.wait([video.initialize(), _subtitles])
        .then((results) {
          final subs = results[1] as List<Subtitle>;
          // Abaikan jika kualitas sudah diganti lagi sebelum video ini siap.
          if (!mounted || video != _video) return;
          video.setPlaybackSpeed(speed);
          setState(() {
            _chewie = ChewieController(
              videoPlayerController: video,
              autoPlay: true,
              startAt: start > Duration.zero ? start : null,
              aspectRatio: _video.value.aspectRatio,
              // Kontrol versi desktop chewie menelan klik tombol di web,
              // jadi semua platform memakai kontrol versi HP.
              customControls: const MaterialControls(),
              // Tombol CC muncul jika ada subtitle; mati di awal karena
              // subtitle Internet Archive umumnya hasil transkripsi otomatis.
              subtitle: subs.isEmpty ? null : Subtitles(subs),
              showSubtitles: false,
              subtitleBuilder: (context, text) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.black54,
                child: Text('$text',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              optionsBuilder: (_, _) => _showSettings(),
              materialProgressColors: ChewieProgressColors(
                playedColor: AppColors.accent,
                handleColor: AppColors.accent,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white12,
              ),
            );
          });
        })
        .catchError((Object e) {
          if (mounted && video == _video) {
            setState(() => _error = 'Video gagal dimuat.');
          }
        });
  }

  void _changeQuality(String quality) {
    if (quality == _quality) return;
    final oldVideo = _video;
    final oldChewie = _chewie;
    final value = oldVideo.value;
    setState(() {
      _quality = quality;
      _lastQuality = quality;
      _chewie = null;
      _error = null;
    });
    // Lanjut dari detik dan kecepatan yang sama dengan sumber baru.
    _load(start: value.position, speed: value.playbackSpeed);
    // Pemutar lama dibuang setelah frame ini, saat widget Chewie-nya sudah dilepas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldChewie?.dispose();
      oldVideo.dispose();
    });
  }

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> _showSettings() {
    // Pakai context halaman ini (di bawah Navigator utama), bukan context kontrol chewie.
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final current = _video.value.playbackSpeed;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.speed_rounded, color: AppColors.muted),
                      SizedBox(width: 10),
                      Text(
                        'Kecepatan putar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final speed in _speeds)
                  ListTile(
                    title: Text(speed == 1.0 ? 'Normal' : '${speed}x'),
                    trailing: speed == current
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.accent,
                          )
                        : null,
                    onTap: () {
                      _video.setPlaybackSpeed(speed);
                      Navigator.pop(sheetContext);
                    },
                  ),
                if (_qualities.isNotEmpty) ...[
                  const Divider(color: Colors.white12, height: 24),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.high_quality_rounded, color: AppColors.muted),
                        SizedBox(width: 10),
                        Text(
                          'Kualitas',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final quality in _qualities)
                    ListTile(
                      title: Text(qualityLabel(quality)),
                      trailing: quality == _quality
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppColors.accent,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _changeQuality(quality);
                      },
                    ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    final value = _video.value;
    if (value.isInitialized) {
      final id = widget.film.id;
      // Disimpan setelah frame ini selesai, karena pohon widget sedang dibongkar.
      Future.microtask(
        () => Library.instance.saveProgress(id, value.position, value.duration),
      );
    }
    _chewie?.dispose();
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.film.title),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: _error != null
            ? Text(_error!)
            : _chewie == null
            ? const CircularProgressIndicator()
            : Chewie(controller: _chewie!),
      ),
    );
  }
}
