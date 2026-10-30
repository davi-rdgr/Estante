import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'app_storage.dart';
import 'score.dart';

/// Conta as páginas de um PDF. Injetável para facilitar testes.
typedef PageCounter = Future<int> Function(String pdfPath);

/// Guarda a biblioteca num SQLite e mantém uma cópia em memória
/// para a UI (a biblioteca de um músico cabe tranquilo na memória).
class ScoreRepository extends ChangeNotifier {
  ScoreRepository._(this.storage, this._db, this._pageCounter) {
    _reload();
  }

  final AppStorage storage;
  final Database _db;
  final PageCounter _pageCounter;
  final _uuid = const Uuid();

  List<Score> _scores = [];
  List<Score> get scores => List.unmodifiable(_scores);

  static const _schemaVersion = 1;

  static ScoreRepository open(AppStorage storage, {required PageCounter pageCounter, Database? database}) {
    final db = database ?? sqlite3.open(storage.databasePath);
    _migrate(db);
    return ScoreRepository._(storage, db, pageCounter);
  }

  static void _migrate(Database db) {
    if (db.userVersion < 1) {
      db.execute('''
        CREATE TABLE IF NOT EXISTS scores (
          id TEXT PRIMARY KEY NOT NULL,
          title TEXT NOT NULL,
          composer TEXT NOT NULL DEFAULT '',
          instrument TEXT NOT NULL DEFAULT '',
          musical_key TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '[]',
          favorite INTEGER NOT NULL DEFAULT 0,
          file_name TEXT NOT NULL,
          original_name TEXT,
          page_count INTEGER NOT NULL DEFAULT 0,
          last_page INTEGER NOT NULL DEFAULT 1,
          added_at INTEGER NOT NULL,
          last_opened_at INTEGER
        )
      ''');
    }
    // Próximas migrações: `if (db.userVersion < 2) { ALTER TABLE ... }`
    db.userVersion = _schemaVersion;
  }

  void _reload() {
    final rows = _db.select('SELECT * FROM scores');
    _scores = [for (final row in rows) Score.fromRow(row)];
    notifyListeners();
  }

  Score? byId(String id) {
    for (final s in _scores) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Todas as tags usadas, em ordem alfabética.
  List<String> get allTags {
    final set = <String>{for (final s in _scores) ...s.tags};
    return set.toList()..sort((a, b) => normalizeForSearch(a).compareTo(normalizeForSearch(b)));
  }

  /// Copia o PDF para a pasta do app e cria a entrada na biblioteca.
  Future<Score> importPdf(String sourcePath) async {
    final id = _uuid.v4();
    final fileName = '$id.pdf';
    final destination = storage.pdfPath(fileName);
    await File(sourcePath).copy(destination);

    var pageCount = 0;
    try {
      pageCount = await _pageCounter(destination);
    } catch (e) {
      // PDF corrompido ou com senha: desfaz a cópia e propaga o erro.
      await File(destination).delete().catchError((_) => File(destination));
      rethrow;
    }

    final originalName = p.basename(sourcePath);
    final score = Score(
      id: id,
      title: titleFromFileName(originalName),
      fileName: fileName,
      originalName: originalName,
      pageCount: pageCount,
      addedAt: DateTime.now(),
    );
    _insert(score);
    _reload();
    return score;
  }

  void _insert(Score score) {
    final row = score.toRow();
    final columns = row.keys.join(', ');
    final placeholders = List.filled(row.length, '?').join(', ');
    _db.execute('INSERT INTO scores ($columns) VALUES ($placeholders)', row.values.toList());
  }

  void update(Score score) {
    final row = score.toRow()..remove('id');
    final sets = row.keys.map((k) => '$k = ?').join(', ');
    _db.execute('UPDATE scores SET $sets WHERE id = ?', [...row.values, score.id]);
    _reload();
  }

  void toggleFavorite(Score score) => update(score.copyWith(favorite: !score.favorite));

  /// Registra que a partitura foi aberta e em qual página parou.
  void markOpened(Score score, {int? page}) {
    final current = byId(score.id) ?? score;
    update(current.copyWith(lastOpenedAt: DateTime.now(), lastPage: page));
  }

  Future<void> delete(Score score) async {
    _db.execute('DELETE FROM scores WHERE id = ?', [score.id]);
    for (final path in [storage.pdfPath(score.fileName), storage.annotationsPath(score.id)]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _reload();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }
}

/// "bach_suite-1_preludio.pdf" → "bach suite 1 preludio"
String titleFromFileName(String fileName) {
  final base = p.basenameWithoutExtension(fileName);
  return base.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
