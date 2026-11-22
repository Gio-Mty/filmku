import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backend.dart';
import '../models/film.dart';
import '../models/tv_detail.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/embed_player/embed_view.dart';
import '../widgets/embed_player/vidfast_controller.dart';
import '../widgets/embed_player/watch_party_dialog.dart';
import 'navigation.dart';

/// Pemutar video iframe/embed web (seperti Vidfast) untuk film TMDB
/// dilengkapi PostMessage API: Auto-Resume, Simpan Progres, Kontrol Kustom, & Nonton Bareng.
class EmbedPlayerScreen extends StatefulWidget {
  const EmbedPlayerScreen({super.key, required this.film});
  final Film film;

  @override
  State<EmbedPlayerScreen> createState() => _EmbedPlayerScreenState();
}

class _EmbedPlayerScreenState extends State<EmbedPlayerScreen>
    with WidgetsBindingObserver {
  late final VidFastController _controller;
  String? _activeRoomId;
  bool _isHost = false;
  Timer? _partyPollTimer;
  String _lastSyncedHostAction = '';
  VideoServer _server = VideoServer.vidfast;
  late Film _currentFilm;
  late int _selectedSeason;
  Future<TvDetail>? _tvDetailFuture;
  Future<List<TvEpisode>>? _episodesFuture;
  bool _isLandscape = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Otomatis sembunyikan status bar & navigasi sistem (Immersive Sticky Fullscreen)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _currentFilm = widget.film;
    _selectedSeason = widget.film.seasonNumber ?? 1;

    if (_currentFilm.isTv && _currentFilm.parsedTvId != null) {
      _tvDetailFuture = Backend.tmdbTvDetail(_currentFilm.parsedTvId!);
      _episodesFuture =
          Backend.tmdbTvSeason(_currentFilm.parsedTvId!, _selectedSeason);
    }

    Library.instance.remember(_currentFilm);

    final savedPos = Library.instance.position(_currentFilm.id).inSeconds;

    _controller = VidFastController(
      initialPositionSeconds: savedPos,
      currentTmdbId: _currentFilm.tmdbId ?? _currentFilm.parsedTvId,
      onProgressUpdate: (currentTime, duration) {
        if (duration > 0) {
          Library.instance.saveProgress(
            _currentFilm.id,
            Duration(seconds: currentTime.toInt()),
            Duration(seconds: duration.toInt()),
          );
        }
      },
      onEnded: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _currentFilm.isTv
                    ? 'Episode selesai ditonton!'
                    : 'Film selesai ditonton!',
              ),
              backgroundColor: AppColors.accent,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      onMediaData: (tmdbId, watched, duration) {
        final currentId = _currentFilm.tmdbId ?? _currentFilm.parsedTvId;
        if (currentId == null || tmdbId == currentId) {
          Library.instance.saveProgress(
            _currentFilm.id,
            Duration(seconds: watched.toInt()),
            Duration(seconds: duration.toInt()),
          );
        }
      },
      onPartyAction: (action, time) {
        if (_activeRoomId != null && _isHost) {
          Backend.syncWatchParty(_activeRoomId!, action, time)
              .catchError((_) => <String, dynamic>{});
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _partyPollTimer?.cancel();
    if (_controller.duration > 0) {
      Library.instance.saveProgress(
        _currentFilm.id,
        Duration(seconds: _controller.currentTime.toInt()),
        Duration(seconds: _controller.duration.toInt()),
      );
    }
    // Kembalikan orientasi dan status bar sistem saat keluar pemutar
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    _controller.dispose();
    super.dispose();
  }

  void _toggleRotation() {
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        _isLandscape = true;
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        _isLandscape = false;
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  void _openWatchParty() {
    showDialog<void>(
      context: context,
      builder: (_) => WatchPartyDialog(
        activeRoomId: _activeRoomId,
        onJoinRoom: (roomId, isHost) {
          setState(() {
            _activeRoomId = roomId;
            _isHost = isHost;
          });
          _startPartySync();
        },
        onLeaveRoom: () {
          setState(() {
            _activeRoomId = null;
            _isHost = false;
          });
          _partyPollTimer?.cancel();
        },
      ),
    );
  }

  void _startPartySync() {
    _partyPollTimer?.cancel();
    if (_isHost) return; // Host memancarkan event saat aksi pengguna

    // Peserta polling status dari Host setiap 1.5 detik
    _partyPollTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (_activeRoomId == null || !mounted) return;
      try {
        final state = await Backend.getWatchParty(_activeRoomId!);
        final action = state['action'] as String;
        final targetTime = (state['time'] as num).toDouble();

        // Cek apakah ada perubahan aksi atau selisih waktu > 2.5 detik
        final diff = (_controller.currentTime - targetTime).abs();
        if (action != _lastSyncedHostAction || diff > 2.5) {
          _lastSyncedHostAction = action;

          if (diff > 2.0) {
            _controller.seek(targetTime, fromParty: true);
          }

          if (action == 'play' && !_controller.isPlaying) {
            _controller.play(fromParty: true);
          } else if (action == 'pause' && _controller.isPlaying) {
            _controller.pause(fromParty: true);
          }
        }
      } catch (_) {}
    });
  }

  void _showSubtitleHelp() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.subtitles_rounded,
                        color: AppColors.accent, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Bantuan Sinkronisasi Subtitle',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Jika subtitle Indonesia terlambat atau terlalu cepat:\n\n'
                  '1. Gunakan Server VidLink (Paling Pas & Tanpa Iklan):\n'
                  '   Pilih server "VidLink (No Ads)". VidLink memiliki subtitle multi-bahasa yang otomatis sinkron dengan audio video.\n\n'
                  '2. Atur Delay di Player VidFast:\n'
                  '   Di dalam player VidFast, klik layar video > klik ikon Gear (⚙️) atau ikon CC di kanan bawah > pilih "Subtitle Offset / Delay". Anda bisa memajukan/memundurkan delay subtitle (+0.5s / -0.5s).\n\n'
                  '3. Ganti ke Server Alternatif Lain:\n'
                  '   Jika subtitle masih kurang pas, coba beralih ke "VidSrc (Baru)" atau "2Embed".',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.dns_rounded),
                    label: const Text(
                      'Ganti ke Server VidLink (No Ads)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (_server != VideoServer.vidlink) {
                        setState(() => _server = VideoServer.vidlink);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showServerPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Pilih Server Pemutar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Divider(color: Colors.white12),
              for (final s in VideoServer.values)
                ListTile(
                  leading: Icon(
                    s == _server
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: s == _server ? AppColors.accent : Colors.white38,
                  ),
                  title: Text(
                    s.label,
                    style: TextStyle(
                      color: s == _server ? AppColors.accent : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    s.description,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (s != _server) {
                      setState(() => _server = s);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEpisodePicker() {
    final tid = _currentFilm.parsedTvId;
    if (tid == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.88,
          expand: false,
          builder: (_, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pilih Episode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              if (_tvDetailFuture != null)
                FutureBuilder<TvDetail>(
                  future: _tvDetailFuture,
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
                          final isSelected = s.seasonNumber == _selectedSeason;
                          return ChoiceChip(
                            label: Text(
                              s.name.isNotEmpty
                                  ? s.name
                                  : 'Season ${s.seasonNumber}',
                            ),
                            selected: isSelected,
                            selectedColor: AppColors.accent,
                            backgroundColor: Colors.white10,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                            onSelected: (_) {
                              setSheetState(() {
                                _selectedSeason = s.seasonNumber;
                                _episodesFuture = Backend.tmdbTvSeason(
                                    tid, _selectedSeason);
                              });
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              const Divider(color: Colors.white12, height: 16),
              Expanded(
                child: FutureBuilder<List<TvEpisode>>(
                  future: _episodesFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.accent),
                      );
                    }
                    final list = snap.data ?? const [];
                    if (list.isEmpty) {
                      return const Center(
                        child: Text(
                          'Episode belum tersedia.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Colors.white10),
                      itemBuilder: (context, i) {
                        final ep = list[i];
                        final isCurrent =
                            _currentFilm.seasonNumber == _selectedSeason &&
                                _currentFilm.episodeNumber == ep.episodeNumber;
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppColors.accent
                                  : Colors.white12,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${ep.episodeNumber}',
                                style: TextStyle(
                                  color: isCurrent ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            ep.name.isNotEmpty
                                ? ep.name
                                : 'Episode ${ep.episodeNumber}',
                            style: TextStyle(
                              color: isCurrent ? AppColors.accent : Colors.white,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: ep.overview.isNotEmpty
                              ? Text(
                                  ep.overview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.muted),
                                )
                              : null,
                          trailing: Icon(
                            isCurrent
                                ? Icons.play_arrow_rounded
                                : Icons.play_circle_outline_rounded,
                            color: isCurrent
                                ? AppColors.accent
                                : Colors.white38,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (!isCurrent) {
                              if (_controller.duration > 0) {
                                Library.instance.saveProgress(
                                  _currentFilm.id,
                                  Duration(
                                      seconds: _controller.currentTime.toInt()),
                                  Duration(
                                      seconds: _controller.duration.toInt()),
                                );
                              }
                              final newFilm = _currentFilm.copyWith(
                                id: 'tmdb-tv-$tid-s$_selectedSeason-e${ep.episodeNumber}',
                                title:
                                    '${widget.film.title} - S$_selectedSeason:E${ep.episodeNumber}',
                                seasonNumber: _selectedSeason,
                                episodeNumber: ep.episodeNumber,
                              );
                              Library.instance.remember(newFilm);
                              setState(() {
                                _currentFilm = newFilm;
                              });
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final embedUrl = _currentFilm.embedUrlForServer(_server);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen
            ? null
            : AppBar(
                backgroundColor: const Color(0xFF141416),
                elevation: 0,
                leading: IconButton(
                  tooltip: 'Kembali',
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentFilm.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Row(
                      children: [
                        if (_currentFilm.isTv &&
                            _currentFilm.episodeNumber != null)
                          Text(
                            'S$_selectedSeason:E${_currentFilm.episodeNumber} • ',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.accent,
                                fontWeight: FontWeight.bold),
                          ),
                        Text(
                          _server.label,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.muted),
                        ),
                        if (_activeRoomId != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'NOBAR: $_activeRoomId',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                actions: [
                  if (_currentFilm.isTv && _currentFilm.parsedTvId != null)
                    IconButton(
                      tooltip: 'Pilih Episode',
                      icon: const Icon(Icons.video_library_rounded,
                          size: 20, color: Colors.white),
                      onPressed: _showEpisodePicker,
                    ),
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => IconButton(
                      tooltip: _controller.isZoomedToFill
                          ? 'Rasio Normal (16:9)'
                          : 'Isi Layar Penuh (Zoom)',
                      icon: Icon(
                        _controller.isZoomedToFill
                            ? Icons.fit_screen_rounded
                            : Icons.aspect_ratio_rounded,
                        size: 20,
                        color: _controller.isZoomedToFill
                            ? AppColors.accent
                            : Colors.white,
                      ),
                      onPressed: _controller.toggleZoomToFill,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bantuan Subtitle',
                    icon: const Icon(Icons.subtitles_rounded,
                        size: 20, color: Colors.white),
                    onPressed: _showSubtitleHelp,
                  ),
                  IconButton(
                    tooltip: 'Rotasi Layar',
                    icon: Icon(
                      _isLandscape
                          ? Icons.screen_lock_landscape_rounded
                          : Icons.screen_rotation_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    onPressed: _toggleRotation,
                  ),
                  IconButton(
                    tooltip: 'Layar Penuh (100% Fullscreen)',
                    icon: const Icon(Icons.fullscreen_rounded,
                        size: 24, color: Colors.white),
                    onPressed: _toggleFullscreen,
                  ),
                  IconButton(
                    tooltip: 'Ganti Server Pemutar',
                    icon: const Icon(Icons.dns_rounded,
                        size: 20, color: Colors.white),
                    onPressed: _showServerPicker,
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: _activeRoomId != null
                            ? AppColors.accent
                            : Colors.white,
                        backgroundColor: Colors.white10,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      icon: const Icon(Icons.groups_rounded, size: 18),
                      label: Text(
                        _activeRoomId != null ? 'Room Nobar' : 'Nobar',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _openWatchParty,
                    ),
                  ),
                ],
              ),
        body: embedUrl == null
            ? const Center(
                child: Text(
                  'Tautan video tidak tersedia.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: KeyedSubtree(
                      key: ValueKey('embed-${_server.name}-${_currentFilm.id}'),
                      child: buildPlatformEmbedView(
                        url: embedUrl,
                        filmId: _currentFilm.id,
                        controller: _controller,
                        onOpenExternal: () => openLink(context, embedUrl),
                      ),
                    ),
                  ),
                  if (_isFullscreen) ...[
                    // Pojok Kiri Atas: Keluar Layar Penuh & Judul
                    Positioned(
                      top: 12,
                      left: 12,
                      child: SafeArea(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xBB000000),
                            borderRadius: BorderRadius.circular(24),
                            border:
                                Border.all(color: Colors.white24, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Keluar Layar Penuh',
                                icon: const Icon(
                                  Icons.fullscreen_exit_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: _toggleFullscreen,
                              ),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 160),
                                child: Text(
                                  _currentFilm.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Pojok Kanan Atas: Mini Dock (Zoom, Episode, Server, Subtitle, Rotasi)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: SafeArea(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xBB000000),
                            borderRadius: BorderRadius.circular(24),
                            border:
                                Border.all(color: Colors.white24, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListenableBuilder(
                                listenable: _controller,
                                builder: (context, _) => IconButton(
                                  tooltip: _controller.isZoomedToFill
                                      ? 'Rasio Normal (16:9)'
                                      : 'Isi Layar Penuh (Zoom)',
                                  icon: Icon(
                                    _controller.isZoomedToFill
                                        ? Icons.fit_screen_rounded
                                        : Icons.aspect_ratio_rounded,
                                    color: _controller.isZoomedToFill
                                        ? AppColors.accent
                                        : Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: _controller.toggleZoomToFill,
                                ),
                              ),
                              if (_currentFilm.isTv &&
                                  _currentFilm.parsedTvId != null)
                                IconButton(
                                  tooltip: 'Pilih Episode',
                                  icon: const Icon(
                                    Icons.video_library_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: _showEpisodePicker,
                                ),
                              IconButton(
                                tooltip: 'Ganti Server',
                                icon: const Icon(
                                  Icons.dns_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: _showServerPicker,
                              ),
                              IconButton(
                                tooltip: 'Bantuan Subtitle',
                                icon: const Icon(
                                  Icons.subtitles_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: _showSubtitleHelp,
                              ),
                              IconButton(
                                tooltip: 'Rotasi Layar',
                                icon: Icon(
                                  _isLandscape
                                      ? Icons.screen_lock_landscape_rounded
                                      : Icons.screen_rotation_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: _toggleRotation,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
