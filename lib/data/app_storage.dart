import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pastas onde o app guarda seus dados.
///
/// No Windows fica em `%APPDATA%\br.com.davi\Estante\Biblioteca`:
/// - `library.db`   → banco SQLite com os metadados
/// - `files/`       → cópias dos PDFs importados
/// - `annotations/` → um JSON de anotações por partitura
class AppStorage {
  AppStorage._(this.root);

  final Directory root;

  Directory get filesDir => Directory(p.join(root.path, 'files'));
  Directory get annotationsDir => Directory(p.join(root.path, 'annotations'));
  String get databasePath => p.join(root.path, 'library.db');

  String pdfPath(String fileName) => p.join(filesDir.path, fileName);
  String annotationsPath(String scoreId) => p.join(annotationsDir.path, '$scoreId.json');

  static Future<AppStorage> open({Directory? rootOverride}) async {
    final root = rootOverride ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'Biblioteca'));
    final storage = AppStorage._(root);
    await storage.filesDir.create(recursive: true);
    await storage.annotationsDir.create(recursive: true);
    return storage;
  }
}
