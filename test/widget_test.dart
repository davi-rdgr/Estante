import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:estante/annotations/annotation_controller.dart';
import 'package:estante/annotations/annotation_models.dart';
import 'package:estante/data/app_storage.dart';
import 'package:estante/data/score.dart';
import 'package:estante/data/score_repository.dart';
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
      expect(repo.allTags, ['Estudo', 'Violoncelo']);
      expect(loaded.searchText, contains('preludio'));

      await repo.delete(loaded);
      expect(repo.scores, isEmpty);
      expect(File(storage.pdfPath(score.fileName)).existsSync(), isFalse);
      repo.dispose();
    });

    test('desfaz a cópia se o PDF não abrir', () async {
      final storage = await AppStorage.open(rootOverride: tmp);
      final source = File(p.join(tmp.path, 'quebrado.pdf'))..writeAsBytesSync([0]);
      final repo = ScoreRepository.open(storage, pageCounter: (_) async => throw Exception('pdf inválido'));
      await expectLater(repo.importPdf(source.path), throwsException);
      expect(repo.scores, isEmpty);
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
      c.tool = AnnotationTool.pen;
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
  });
}
