import 'package:flutter/material.dart';

import 'screens/main_shell.dart';
import 'state/library.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Library.instance.load();
  runApp(const FilmkuApp());
}

class FilmkuApp extends StatelessWidget {
  const FilmkuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Filmku',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const MainShell(),
    );
  }
}
