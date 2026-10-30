import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:estante/annotations/annotation_controller.dart';
import 'package:estante/annotations/annotation_models.dart';
import 'package:estante/data/app_storage.dart';
import 'package:estante/data/score.dart';
import 'package:estante/data/score_repository.dart';
import 'package:estante/screens/library_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('estante_test'));
  tearDown(() async => tmp.delete(recursive: true));

  group('ScoreRepository', () {
    test('importa, edita, persiste e exclui', () async {
      final storage = await AppStorage.open(rootOverride: tmp);
      final source = File(p.join(tmp.path, 'bach_suite-1_preludio.pdf'))..writeAsBytesSync([1, 2, 3]);

      var repo = ScoreRepository.open(storage, pageCounter: (_) async => 4);
      final score = await repo.importPdf(source.path);
      expect(score.title, 'bach suite 1 preludio');
      expect(score.pageCount, 4);
      expect(File(storage.pdfPath(score.fileName)).existsSync(), isTrue);

      repo.update(score.copyWith(composer: 'J. S. Bach', tags: ['Violoncelo', 'Estudo'], favorite: true));
      repo.dispose();

      // Reabre o banco: dados devem continuar lá.
      repo = ScoreRepository.open(storage, pageCounter: (_) async => 0);
      final loaded = repo.byId(score.id)!;
      expect(loaded.composer, 'J. S. Bach');
      expect(loaded.tags, ['Violoncelo', 'Estudo']);
      expect(loaded.favorite, isTrue);
      expect(repo.allTags.value, ['Estudo', 'Violoncelo']);
      expect(loaded.searchText, contains('preludio'));

      await repo.delete(loaded);
      expect(repo.scores.value, isEmpty);
      expect(File(storage.pdfPath(score.fileName)).existsSync(), isFalse);
      repo.dispose();
    });

    test('exclusão some da lista mesmo se o arquivo estiver travado', () async {
      final storage = await AppStorage.open(rootOverride: tmp);
      final source = File(p.join(tmp.path, 'a.pdf'))..writeAsBytesSync([1]);
      var repo = ScoreRepository.open(storage, pageCounter: (_) async => 1);
      final score = await repo.importPdf(source.path);

      // Simula o PDF em uso: um diretório no lugar do arquivo faz o delete falhar.
      final pdf = File(storage.pdfPath(score.fileName))..deleteSync();
      Directory(pdf.path).createSync();
      await repo.delete(score);
      expect(repo.scores.value, isEmpty);
      repo.dispose();

      // Órfãos (arquivos sem partitura) são limpos ao abrir de novo.
      Directory(pdf.path).deleteSync();
      final orphan = File(storage.pdfPath('sobra.pdf'))..writeAsBytesSync([1]);
      final orphanNotes = File(storage.annotationsPath('sumiu'))..writeAsStringSync('{}');
      repo = ScoreRepository.open(storage, pageCounter: (_) async => 1);
      expect(orphan.existsSync(), isFalse);
      expect(orphanNotes.existsSync(), isFalse);
      repo.dispose();
    });

    test('desfaz a cópia se o PDF não abrir', () async {
      final storage = await AppStorage.open(rootOverride: tmp);
      final source = File(p.join(tmp.path, 'quebrado.pdf'))..writeAsBytesSync([0]);
      final repo = ScoreRepository.open(storage, pageCounter: (_) async => throw Exception('pdf inválido'));
      await expectLater(repo.importPdf(source.path), throwsException);
      expect(repo.scores.value, isEmpty);
      expect(storage.filesDir.listSync(), isEmpty);
      repo.dispose();
    });
  });

  test('busca ignora acentos e maiúsculas', () {
    expect(normalizeForSearch('Prelúdio em Ré Menor'), 'preludio em re menor');
  });

  group('AnnotationController', () {
    test('desenha, desfaz, refaz, apaga e salva', () async {
      final path = p.join(tmp.path, 'a.json');
      final c = AnnotationController(filePath: path, autosaveDelay: const Duration(hours: 1));
      c.tool.value = AnnotationTool.pen;
      c.beginStroke(1, const Offset(0.1, 0.1));
      c.extendStroke(const Offset(0.5, 0.5));
      c.endStroke();
      c.addText(2, const Offset(0.2, 0.2), 'rit.');
      expect(c.itemsFor(1), hasLength(1));
      expect(c.itemsFor(2).single, isA<TextNote>());

      c.undo();
      expect(c.itemsFor(2), isEmpty);
      c.redo();
      expect(c.itemsFor(2), hasLength(1));

      // Borracha no meio do traço remove o traço.
      c.eraseAt(1, const Offset(0.3, 0.3), 5, const Size(600, 800));
      expect(c.itemsFor(1), isEmpty);
      c.undo();

      await c.save();
      final reloaded = AnnotationController(filePath: path);
      await reloaded.load();
      final stroke = reloaded.itemsFor(1).single as InkStroke;
      expect(stroke.points.last, const Offset(0.5, 0.5));
      expect((reloaded.itemsFor(2).single as TextNote).text, 'rit.');
      c.dispose();
      reloaded.dispose();
    });

    test('signals: cor por ferramenta, desfazer e traço ativo', () {
      final c = AnnotationController(filePath: p.join(tmp.path, 'b.json'), autosaveDelay: const Duration(hours: 1));
      expect(c.isEditing.value, isFalse);

      // Caneta e marca-texto guardam cores separadas.
      c.tool.value = AnnotationTool.pen;
      c.setColor(AnnotationController.palette[2]);
      c.tool.value = AnnotationTool.highlighter;
      expect(c.color.value, AnnotationController.palette[4]);
      c.tool.value = AnnotationTool.pen;
      expect(c.color.value, AnnotationController.palette[2]);

      // O traço ativo é mutado no lugar, mas precisa avisar quem escuta.
      var notified = 0;
      final stop = c.activeStroke.subscribe((_) => notified++);
      notified = 0; // subscribe chama uma vez na hora
      c.beginStroke(1, const Offset(0.1, 0.1));
      c.extendStroke(const Offset(0.2, 0.2));
      c.extendStroke(const Offset(0.3, 0.3));
      expect(notified, 3);
      stop();

      expect(c.canUndo.value, isFalse);
      c.endStroke();
      expect(c.activeStroke.value, isNull);
      expect(c.canUndo.value, isTrue);
      c.undo();
      expect(c.canUndo.value, isFalse);
      expect(c.canRedo.value, isTrue);
      c.dispose();
    });
  });

  group('LibraryController', () {
    test('busca, filtros e ordenação reagem ao repositório', () async {
      final storage = await AppStorage.open(rootOverride: tmp);
      final repo = ScoreRepository.open(storage, pageCounter: (_) async => 1);
      Future<Score> add(String name) {
        final file = File(p.join(tmp.path, name))..writeAsBytesSync([1]);
        return repo.importPdf(file.path);
      }

      final bach = await add('Prelúdio Bach.pdf');
      final faure = await add('Elegia Fauré.pdf');
      final library = LibraryController(repo);
      library.sort.value = ScoreSort.title;
      List<String> titles() => [for (final s in library.visibleScores.value) s.title];

      expect(titles(), ['Elegia Fauré', 'Prelúdio Bach']);

      library.query.value = 'preludio';
      expect(titles(), ['Prelúdio Bach']);
      library.query.value = '';

      // Mudança no repositório chega no computed sem ninguém avisar.
      repo.update(faure.copyWith(tags: ['Recital']));
      library.toggleTag('Recital', true);
      expect(titles(), ['Elegia Fauré']);
      library.toggleTag('Recital', false);

      repo.toggleFavorite(bach);
      library.onlyFavorites.value = true;
      expect(titles(), ['Prelúdio Bach']);

      library.dispose();
      repo.dispose();
    });
  });
}
