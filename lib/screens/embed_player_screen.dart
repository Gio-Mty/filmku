import 'dart:async';
import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../models/film.dart';
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

class _EmbedPlayerScreenState extends State<EmbedPlayerScreen> {
  late final VidFastController _controller;
  String? _activeRoomId;
  bool _isHost = false;
  Timer? _partyPollTimer;
  String _lastSyncedHostAction = '';
  VideoServer _server = VideoServer.vidfast;

  @override
  void initState() {
    super.initState();
    Library.instance.remember(widget.film);

    final savedPos = Library.instance.position(widget.film.id).inSeconds;

    _controller = VidFastController(
      initialPositionSeconds: savedPos,
      onProgressUpdate: (currentTime, duration) {
        if (duration > 0) {
          Library.instance.saveProgress(
            widget.film.id,
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
                widget.film.isTv
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
        Library.instance.saveProgress(
          widget.film.id,
          Duration(seconds: watched.toInt()),
          Duration(seconds: duration.toInt()),
        );
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
  void dispose() {
    _partyPollTimer?.cancel();
    if (_controller.duration > 0) {
      Library.instance.saveProgress(
        widget.film.id,
        Duration(seconds: _controller.currentTime.toInt()),
        Duration(seconds: _controller.duration.toInt()),
      );
    }
    _controller.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final embedUrl = widget.film.embedUrlForServer(_server);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
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
              widget.film.title,
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
                Text(
                  _server.label,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                if (_activeRoomId != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          IconButton(
            tooltip: 'Ganti Server Pemutar',
            icon: const Icon(Icons.dns_rounded, size: 20, color: Colors.white),
            onPressed: _showServerPicker,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor:
                    _activeRoomId != null ? AppColors.accent : Colors.white,
                backgroundColor: Colors.white10,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          : KeyedSubtree(
              key: ValueKey('embed-${_server.name}-${widget.film.id}'),
              child: buildPlatformEmbedView(
                url: embedUrl,
                filmId: widget.film.id,
                controller: _controller,
                onOpenExternal: () => openLink(context, embedUrl),
              ),
            ),
    );
  }
}
