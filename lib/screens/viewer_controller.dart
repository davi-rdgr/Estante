import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../annotations/annotation_controller.dart';
import '../annotations/annotation_models.dart';
import '../data/score.dart';
import '../data/score_repository.dart';

/// Estado do leitor de uma partitura: documento aberto, página atual,
/// modo 1/2 páginas, zoom e anotações.
///
/// Criado e descartado pela [ViewerScreen]. O descarte precisa ser no
/// `dispose` do State (e não ao fechar a rota) porque a animação de
/// saída ainda desenha as páginas do PDF.
class ViewerController {
  ViewerController({required this.score, required this.repository})
    : annotations = AnnotationController(filePath: repository.storage.annotationsPath(score.id)),
      page = signal(score.lastPage);

  final Score score;
  final ScoreRepository repository;
  final AnnotationController annotations;
  final transform = TransformationController();

  final document = signal<PdfDocument?>(null);
  final error = signal<Object?>(null);

  /// Primeira página visível (1-based).
  final FlutterSignal<int> page;
  final twoPages = signal(false);

  bool _disposed = false;

  late final FlutterReadonlySignal<int> pageCount = computed(() => document.value?.pages.length ?? 0);
  late final FlutterReadonlySignal<int> step = computed(() => twoPages.value ? 2 : 1);

  /// Páginas na tela agora (uma ou duas).
  late final FlutterReadonlySignal<List<int>> visiblePages = computed(() {
    final first = page.value, count = pageCount.value;
    return [for (var p = first; p < first + step.value && p <= count; p++) p];
  });

  late final FlutterReadonlySignal<bool> canGoNext = computed(() => page.value + step.value <= pageCount.value);
  late final FlutterReadonlySignal<bool> canGoPrevious = computed(() => page.value > 1);

  /// "3 / 10" ou "3–4 / 10".
  late final FlutterReadonlySignal<String> pageLabel = computed(() {
    final count = pageCount.value;
    if (count == 0) return '';
    final pages = visiblePages.value;
    return pages.length > 1 ? '${pages.first}–${pages.last} / $count' : '${page.value} / $count';
  });

  bool get isZoomed => transform.value.getMaxScaleOnAxis() > 1.01;

  /// Abre o PDF e as anotações. [isWideScreen] é consultado só no fim,
  /// para decidir se começa em modo estante (duas páginas).
  Future<void> open({required bool Function() isWideScreen}) async {
    try {
      final doc = await PdfDocument.openFile(repository.storage.pdfPath(score.fileName));
      await annotations.load();
      if (_disposed) {
        await doc.dispose();
        return;
      }
      batch(() {
        document.value = doc;
        page.value = page.value.clamp(1, math.max(1, doc.pages.length));
        twoPages.value = doc.pages.length > 1 && isWideScreen();
      });
      repository.markOpened(score, page: page.value);
    } catch (e) {
      if (!_disposed) error.value = e;
    }
  }

  // ---------- navegação ----------

  void goTo(int target) {
    if (pageCount.value == 0) return;
    final clamped = target.clamp(1, pageCount.value);
    if (clamped == page.value) return;
    page.value = clamped;
    resetZoom();
  }

  void next() {
    if (canGoNext.value) goTo(page.value + step.value);
  }

  void previous() => goTo(page.value - step.value);
  void first() => goTo(1);
  void last() => goTo(pageCount.value);
  void toggleTwoPages() => twoPages.value = !twoPages.value;
  void resetZoom() => transform.value = Matrix4.identity();

  /// Alterna a ferramenta; escolher a que já está ativa volta ao modo leitura.
  void toggleTool(AnnotationTool? tool) => annotations.tool.value = annotations.tool.value == tool ? null : tool;

  void dispose() {
    _disposed = true;
    annotations.save();
    annotations.dispose();
    final doc = document.value;
    if (doc != null) {
      // Fora do dispose: atualizar o repositório reconstrói a biblioteca,
      // e não se pode reconstruir widgets enquanto a árvore está travada.
      final repo = repository, score = this.score, page = this.page.value;
      Future.microtask(() => repo.markOpened(score, page: page));
      doc.dispose();
    }
    transform.dispose();
  }
}
