import 'dart:convert';

import 'package:chewie/chewie.dart';
import 'package:http/http.dart' as http;

/// Unduh dan parse subtitle .srt atau .vtt. Kosong jika gagal; subtitle bukan hal wajib.
Future<List<Subtitle>> loadSubtitles(String url) async {
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];
    return parseSubtitles(utf8.decode(res.bodyBytes, allowMalformed: true));
  } catch (_) {
    return const [];
  }
}

final _time = RegExp(r'(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})');

/// Format SRT dan WebVTT sama-sama berupa blok berisi baris `mulai --> selesai`
/// diikuti teks; nomor urut (SRT) dan header `WEBVTT` diabaikan.
List<Subtitle> parseSubtitles(String raw) {
  final blocks = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n\s*\n'));
  final result = <Subtitle>[];
  for (final block in blocks) {
    final lines = block.split('\n');
    final i = lines.indexWhere((l) => l.contains('-->'));
    if (i < 0) continue;
    final parts = lines[i].split('-->');
    final start = _parse(parts[0]);
    final end = _parse(parts[1]);
    final text = lines
        .skip(i + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]+>'), '') // tag gaya VTT seperti <i> atau <c.yellow>
        .trim();
    if (start == null || end == null || text.isEmpty) continue;
    result.add(Subtitle(index: result.length, start: start, end: end, text: text));
  }
  return result;
}

Duration? _parse(String s) {
  final m = _time.firstMatch(s);
  if (m == null) return null;
  return Duration(
    hours: int.parse(m.group(1) ?? '0'),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: int.parse(m.group(4)!.padRight(3, '0')),
  );
}
