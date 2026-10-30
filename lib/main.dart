import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'data/app_storage.dart';
import 'data/score_repository.dart';
import 'screens/library_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  final storage = await AppStorage.open();
  final repository = ScoreRepository.open(storage, pageCounter: _countPages);

  runApp(PartiturasApp(repository: repository));
}

Future<int> _countPages(String path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    return doc.pages.length;
  } finally {
    await doc.dispose();
  }
}

class PartiturasApp extends StatelessWidget {
  const PartiturasApp({super.key, required this.repository});

  final ScoreRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Estante',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: LibraryScreen(repository: repository),
    );
  }
}
