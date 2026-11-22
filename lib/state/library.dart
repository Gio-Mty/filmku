import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/films.dart';
import '../models/film.dart';

/// Daftarku, riwayat tonton, dan posisi terakhir tiap film. Disimpan di perangkat.
class Library extends ChangeNotifier {
  Library._();
  static final instance = Library._();

  SharedPreferences? _prefs;
  final Set<String> _saved = {};
  // Film Internet Archive dan episode serial yang disimpan atau pernah diputar.
  // Tidak ada di data lokal, jadi datanya ikut disimpan.
  final Map<String, Film> _remote = {};
  final List<String> _history = [];
  final Map<String, List<int>> _progress = {}; // id -> [posisi detik, durasi detik]

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _saved.addAll(_prefs!.getStringList('saved') ?? const []);
    _history.addAll(_prefs!.getStringList('history') ?? const []);
    final remote = _prefs!.getString('remote_films');
    if (remote != null) {
      for (final j in jsonDecode(remote) as List) {
        final f = Film.fromJson(j as Map<String, dynamic>);
        _remote[f.id] = f;
      }
    }
    final raw = _prefs!.getString('progress');
    if (raw != null) {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((id, v) {
        _progress[id] = (v as List).cast<int>();
      });
    }
  }

  bool isSaved(String id) => _saved.contains(id);

  void toggleSaved(Film film) {
    if (!_saved.remove(film.id)) {
      _saved.add(film.id);
      remember(film);
    }
    _prefs?.setStringList('saved', _saved.toList());
    _pruneRemote();
    notifyListeners();
  }

  /// Simpan data film remote supaya muncul lagi di Daftarku/riwayat setelah app dibuka ulang.
  void remember(Film film) {
    if (!film.isRemote) return;
    _remote[film.id] = film;
    _persistRemote();
  }

  void _pruneRemote() {
    _remote.removeWhere((id, _) => !_saved.contains(id) && !_history.contains(id));
    _persistRemote();
  }

  void _persistRemote() => _prefs?.setString(
      'remote_films', jsonEncode(_remote.values.map((f) => f.toJson()).toList()));

  Film? _find(String id) => filmById(id) ?? _remote[id];

  List<Film> get savedFilms => _saved.map(_find).whereType<Film>().toList();

  List<Film> get historyFilms => _history.map(_find).whereType<Film>().toList();

  Duration position(String id) => Duration(seconds: _progress[id]?[0] ?? 0);

  /// 0.0 sampai 1.0; 0 berarti belum ditonton atau sudah selesai.
  double progress(String id) {
    final p = _progress[id];
    if (p == null || p[1] == 0) return 0;
    return (p[0] / p[1]).clamp(0.0, 1.0);
  }

  void saveProgress(String id, Duration position, Duration duration) {
    if (duration.inSeconds == 0) return;
    final finished = position.inSeconds >= duration.inSeconds - 5;
    _progress[id] = [finished ? 0 : position.inSeconds, duration.inSeconds];
    _history
      ..remove(id)
      ..insert(0, id);
    _prefs?.setString('progress', jsonEncode(_progress));
    _prefs?.setStringList('history', _history);
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _progress.clear();
    _prefs?.remove('history');
    _prefs?.remove('progress');
    _pruneRemote();
    notifyListeners();
  }
}
