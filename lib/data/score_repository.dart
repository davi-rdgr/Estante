import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'app_storage.dart';
import 'score.dart';

/// Conta as páginas de um PDF. Injetável para facilitar testes.
typedef PageCounter = Future<int> Function(String pdfPath);

/// Guarda a biblioteca num SQLite e mantém uma cópia em memória
/// para a UI (a biblioteca de um músico cabe tranquilo na memória).
/// A cópia é um signal: quem lê [scores] dentro de um build ou
/// computed é atualizado sozinho quando o banco muda.
class ScoreRepository {
  ScoreRepository._(this.storage, this._db, this._pageCounter) {
    _reload();
    _deleteOrphanFiles();
  }

  final AppStorage storage;
  final Database _db;
  final PageCounter _pageCounter;
  final _uuid = const Uuid();

  final _scores = signal<List<Score>>(const []);
  FlutterReadonlySignal<List<Score>> get scores => _scores;

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
    _scores.value = List.unmodifiable([for (final row in rows) Score.fromRow(row)]);
  }

  Score? byId(String id) {
    for (final s in _scores.value) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Todas as tags usadas, em ordem alfabética.
  late final FlutterReadonlySignal<List<String>> allTags = computed(() {
    final set = <String>{for (final s in _scores.value) ...s.tags};
    return set.toList()..sort((a, b) => normalizeForSearch(a).compareTo(normalizeForSearch(b)));
  });

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
    // Atualiza a lista antes de mexer nos arquivos: no Windows o PDF pode
    // estar travado (a miniatura ainda está com ele aberto), e a falha ao
    // apagar não pode impedir a partitura de sumir da biblioteca.
    _reload();
    for (final path in [storage.pdfPath(score.fileName), storage.annotationsPath(score.id)]) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Não existe ou está em uso: sobra como órfão e sai na próxima abertura.
      }
    }
  }

  /// Apaga PDFs e anotações que não pertencem a nenhuma partitura
  /// (sobras de exclusões em que o arquivo estava em uso).
  void _deleteOrphanFiles() {
    final pdfs = {for (final s in _scores.value) s.fileName};
    final ids = {for (final s in _scores.value) s.id};
    // Anotações: "<id>.json" e o temporário "<id>.json.tmp".
    final orphans = [
      for (final f in storage.filesDir.listSync().whereType<File>())
        if (!pdfs.contains(p.basename(f.path))) f,
      for (final f in storage.annotationsDir.listSync().whereType<File>())
        if (!ids.contains(p.basename(f.path).split('.').first)) f,
    ];
    for (final file in orphans) {
      try {
        file.deleteSync();
      } on FileSystemException {
        // Fica para a próxima.
      }
    }
  }

  void dispose() => _db.close();
}

/// "bach_suite-1_preludio.pdf" → "bach suite 1 preludio"
String titleFromFileName(String fileName) {
  final base = p.basenameWithoutExtension(fileName);
  return base.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
