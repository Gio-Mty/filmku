import 'package:filmku/main.dart';
import 'package:filmku/state/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Ukuran layar HP (360x780), bukan bawaan tes 800x600.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const FilmkuApp());
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Library.instance.load();
  });

  testWidgets('Beranda menampilkan bagian utama dan navigasi', (tester) async {
    await pumpApp(tester);
    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Sedang Tren Minggu Ini'), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Daftarku'), findsWidgets);
  });

  testWidgets('Tombol Daftarku menyimpan film unggulan', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Daftarku'));
    await tester.pump();
    expect(Library.instance.isSaved('tmdb-1726'), isTrue);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
