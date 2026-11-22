import 'package:filmku/data/archive_service.dart';
import 'package:filmku/data/subtitles.dart';
import 'package:filmku/models/archive_movie.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArchiveMovie.fromJson', () {
    test('year dan description bisa String, int, List, atau null', () {
      final cases = <Object?, int?>{
        '1950': 1950,
        1938: 1938,
        ['1942']: 1942,
        '1950-05-01': 1950,
        'c. 1921?': 1921,
        null: null,
        <String>[]: null,
        'tidak diketahui': null,
      };
      cases.forEach((input, expected) {
        final m = ArchiveMovie.fromJson({'identifier': 'x', 'year': input});
        expect(m.year, expected, reason: 'year: $input');
      });

      expect(ArchiveMovie.fromJson({'identifier': 'x'}).description, '');
      expect(
        ArchiveMovie.fromJson({
          'identifier': 'x',
          'description': ['Bagian <b>satu</b>', 'Bagian dua<br/>baris'],
        }).description,
        'Bagian satu\n\nBagian dua\nbaris',
      );
    });

    test('judul kosong memakai identifier; poster dari identifier', () {
      final m = ArchiveMovie.fromJson({'identifier': 'his_girl_friday', 'downloads': '1320834'});
      expect(m.title, 'his_girl_friday');
      expect(m.downloads, 1320834);
      expect(m.posterUrl, 'https://archive.org/services/img/his_girl_friday');
    });
  });

  group('pickMobileMp4', () {
    test('lewati klip pendek dan master besar, ambil versi penuh yang ringan', () {
      // Cuplikan file asli dari archive.org/metadata/Sita_Sings_the_Blues.
      final files = [
        {'name': 'Sita_Sings_the_Blues_1080p.mp4', 'format': 'h.264 MPEG4', 'size': '4428753160', 'length': '4891.24', 'height': '1080'},
        {'name': 'Sita_Sings_the_Blues.mp4', 'format': 'h.264', 'size': '507536373', 'length': '4891.24', 'height': '360'},
        {'name': 'Sita_Sings_the_Blues_medium.mp4', 'format': 'h.264 MPEG4', 'size': '499842215', 'length': '4891.23', 'height': '272'},
        {'name': 'Sita_Sings_the_Blues_small.mp4', 'format': 'h.264 MPEG4', 'size': '223616052', 'length': '4891.23', 'height': '176'},
        {'name': 'Sita_Sings_the_Blues_DVD_NTSC4.mp4', 'format': 'h.264', 'size': '10937777', 'length': '105.26', 'height': '360'},
        {'name': 'Sita_Sings_the_Blues.ogv', 'format': 'Ogg Video', 'size': '352906907'},
      ];
      expect(pickMobileMp4(files)?['name'], 'Sita_Sings_the_Blues_medium.mp4');
    });

    test('tanpa info durasi/tinggi tetap pilih yang terkecil', () {
      final files = [
        {'name': 'his_girl_friday.mp4', 'format': 'h.264', 'size': '575274912'},
        {'name': 'his_girl_friday_512kb.mp4', 'format': '512Kb MPEG4', 'size': '401207987'},
        {'name': 'his_girl_friday.mpeg', 'format': 'MPEG2', 'size': '3292094468'},
      ];
      expect(pickMobileMp4(files)?['name'], 'his_girl_friday_512kb.mp4');
    });

    test('null jika tidak ada mp4', () {
      expect(pickMobileMp4([{'name': 'a.ogv', 'format': 'Ogg Video'}]), isNull);
    });
  });

  test('pickSubtitle mengutamakan vtt lalu nama yang cocok dengan video', () {
    final files = [
      {'name': 'other.asr.srt'},
      {'name': 'film.asr.srt'},
    ];
    expect(pickSubtitle(files, 'film_512kb.mp4')?['name'], 'film.asr.srt');
    expect(pickSubtitle([...files, {'name': 'x.vtt'}], 'film.mp4')?['name'], 'x.vtt');
  });

  test('parseSubtitles membaca SRT dan VTT', () {
    final srt = parseSubtitles('1\r\n00:00:01,500 --> 00:00:03,000\r\nHalo\r\ndunia\r\n\r\n'
        '2\r\n01:02:03,040 --> 01:02:04,000\r\n<i>Lagi</i>\r\n');
    expect(srt, hasLength(2));
    expect(srt[0].start, const Duration(seconds: 1, milliseconds: 500));
    expect(srt[0].text, 'Halo\ndunia');
    expect(srt[1].start, const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 40));
    expect(srt[1].text, 'Lagi');

    final vtt = parseSubtitles('WEBVTT\n\n00:05.000 --> 00:07.250 align:start\nHai\n');
    expect(vtt.single.start, const Duration(seconds: 5));
    expect(vtt.single.end, const Duration(seconds: 7, milliseconds: 250));
  });
}
