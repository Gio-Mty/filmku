import 'dart:async';
import 'package:flutter/foundation.dart';

/// Controller untuk mengontrol pemutar VidFast secara terprogram
/// melalui PostMessage API (PLAYER_EVENT & MEDIA_DATA).
class VidFastController extends ChangeNotifier {
  VidFastController({
    this.initialPositionSeconds = 0,
    this.onProgressUpdate,
    this.onPartyAction,
    this.onEnded,
    this.onMediaData,
  });

  final int initialPositionSeconds;
  final void Function(double currentTime, double duration)? onProgressUpdate;
  final void Function(String action, double time)? onPartyAction;
  final VoidCallback? onEnded;
  final void Function(int tmdbId, double watched, double duration)? onMediaData;

  double _currentTime = 0;
  double _duration = 0;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;
  bool _isReady = false;
  bool _hasInitialSeeked = false;

  /// Dispatcher yang disuntikkan oleh platform (Web iframe atau Mobile WebView).
  void Function(String command, Map<String, dynamic> params)? commandDispatcher;

  double get currentTime => _currentTime;
  double get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  bool get isReady => _isReady;

  /// Kirim perintah 'play' ke VidFast
  void play({bool fromParty = false}) {
    _sendCommand('play', {});
    _isPlaying = true;
    notifyListeners();
    if (!fromParty) onPartyAction?.call('play', _currentTime);
  }

  /// Kirim perintah 'pause' ke VidFast
  void pause({bool fromParty = false}) {
    _sendCommand('pause', {});
    _isPlaying = false;
    notifyListeners();
    if (!fromParty) onPartyAction?.call('pause', _currentTime);
  }

  void togglePlay() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Lompat ke detik tertentu
  void seek(double time, {bool fromParty = false}) {
    final target = time.clamp(0.0, _duration > 0 ? _duration : 999999.0);
    _sendCommand('seek', {'time': target});
    _currentTime = target;
    notifyListeners();
    if (!fromParty) onPartyAction?.call('seek', target);
  }

  /// Lompat relatif (misal +10 atau -10 detik)
  void seekRelative(double offsetSeconds) {
    seek(_currentTime + offsetSeconds);
  }

  /// Atur volume (0.0 sampai 1.0)
  void setVolume(double level) {
    final v = level.clamp(0.0, 1.0);
    _sendCommand('volume', {'level': v});
    _volume = v;
    notifyListeners();
  }

  /// Toggle mute suara
  void toggleMute() {
    final targetMute = !_isMuted;
    _sendCommand('mute', {'muted': targetMute});
    _isMuted = targetMute;
    notifyListeners();
  }

  /// Minta status terkini dari player
  void getStatus() {
    _sendCommand('getStatus', {});
  }

  /// Dipanggil saat ada pesan PLAYER_EVENT dari VidFast
  void handleEvent(Map<String, dynamic> eventData) {
    _isReady = true;

    final event = eventData['event'] as String?;
    final time = eventData['currentTime'];
    if (time is num) {
      _currentTime = time.toDouble();
    }

    final dur = eventData['duration'];
    if (dur is num && dur > 0) {
      _duration = dur.toDouble();
    }

    final playing = eventData['playing'];
    if (playing is bool) {
      _isPlaying = playing;
    } else if (event == 'play' || event == 'timeupdate') {
      _isPlaying = true;
    } else if (event == 'pause' || event == 'ended') {
      _isPlaying = false;
    }

    final muted = eventData['muted'];
    if (muted is bool) {
      _isMuted = muted;
    }

    final vol = eventData['volume'];
    if (vol is num) {
      _volume = vol.toDouble();
    }

    // Tangani event 'ended'
    if (event == 'ended') {
      _isPlaying = false;
      onEnded?.call();
    }

    // Auto-Resume ke posisi tontonan terakhir jika ada
    if (!_hasInitialSeeked && initialPositionSeconds > 5 && _duration > 10) {
      _hasInitialSeeked = true;
      Timer(const Duration(milliseconds: 600), () {
        seek(initialPositionSeconds.toDouble());
      });
    }

    onProgressUpdate?.call(_currentTime, _duration);
    notifyListeners();
  }

  /// Dipanggil saat ada pesan MEDIA_DATA dari VidFast
  void handleMediaData(Map<String, dynamic> mediaDataMap) {
    _isReady = true;
    for (final entry in mediaDataMap.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        final id = value['id'] as int?;
        final progress = value['progress'];
        if (id != null && progress is Map) {
          final watched = (progress['watched'] as num?)?.toDouble() ?? 0.0;
          final duration = (progress['duration'] as num?)?.toDouble() ?? 0.0;
          if (duration > 0) {
            _currentTime = watched;
            _duration = duration;
            onProgressUpdate?.call(_currentTime, _duration);
            onMediaData?.call(id, watched, duration);
            notifyListeners();
          }
        }
      }
    }
  }

  void _sendCommand(String command, Map<String, dynamic> params) {
    commandDispatcher?.call(command, params);
  }
}
