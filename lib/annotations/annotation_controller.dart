import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'annotation_models.dart';

/// Estado das anotações de uma partitura: itens por página, ferramenta
/// atual, desfazer/refazer e salvamento automático em JSON.
///
/// Tudo que a UI mostra é signal; os widgets que leem `.value` no build
/// se atualizam sozinhos.
class AnnotationController {
  AnnotationController({required this.filePath, this.autosaveDelay = const Duration(milliseconds: 800)});

  final String filePath;
  final Duration autosaveDelay;

  final _pages = signal<Map<int, List<AnnotationItem>>>(const {});
  final _undo = signal<List<_Change>>(const []);
  final _redo = signal<List<_Change>>(const []);
  Timer? _saveTimer;
  bool _dirty = false;

  // ---------- ferramenta ----------

  /// `null` = modo leitura (arrastar move a página, clique vira página).
  final tool = signal<AnnotationTool?>(null);
  late final FlutterReadonlySignal<bool> isEditing = computed(() => tool.value != null);

  static const palette = <Color>[
    Color(0xFF1E2533), // tinta
    Color(0xFFB3312A), // lápis vermelho
    Color(0xFF2B4C8C), // azul
    Color(0xFF2F7D4A), // verde
    Color(0xFFF0C02F), // amarelo (marca-texto)
    Color(0xFF7B3FA0), // roxo
  ];

  final _penColor = signal(palette[1]);
  final _highlighterColor = signal(palette[4]);
  bool get _highlighting => tool.value == AnnotationTool.highlighter;

  /// Cor da ferramenta atual (caneta e marca-texto guardam cada uma a sua).
  late final FlutterReadonlySignal<Color> color = computed(
    () => _highlighting ? _highlighterColor.value : _penColor.value,
  );
  void setColor(Color value) => (_highlighting ? _highlighterColor : _penColor).value = value;

  /// Espessura da caneta como fração da largura da página.
  final _penWidth = signal(0.003);
  final _highlighterWidth = signal(0.018);
  final double textSize = 0.022;

  late final FlutterReadonlySignal<double> strokeWidth = computed(
    () => _highlighting ? _highlighterWidth.value : _penWidth.value,
  );
  void setStrokeWidth(double value) => (_highlighting ? _highlighterWidth : _penWidth).value = value;

  // ---------- leitura ----------

  /// Itens de todas as páginas. Troca de mapa a cada mudança (nunca é
  /// mutado no lugar), então serve de gatilho para repintar.
  FlutterReadonlySignal<Map<int, List<AnnotationItem>>> get pages => _pages;
  List<AnnotationItem> itemsFor(int page) => _pages.value[page] ?? const [];
  late final FlutterReadonlySignal<bool> canUndo = computed(() => _undo.value.isNotEmpty);
  late final FlutterReadonlySignal<bool> canRedo = computed(() => _redo.value.isNotEmpty);

  /// Traço sendo desenhado agora (ainda não confirmado).
  final _active = signal<({int page, InkStroke stroke})?>(null);
  FlutterReadonlySignal<({int page, InkStroke stroke})?> get activeStroke => _active;

  // ---------- gesto em andamento ----------
  // Usado pela camada de desenho. Não é estado de UI, então não é signal.

  /// Ponteiro que está desenhando/apagando; os outros (segundo dedo) são ignorados.
  int? activePointer;
  bool erasing = false;

  /// Última posição da borracha, em pixels da página.
  Offset? lastErase;

  // ---------- edição ----------

  void beginStroke(int page, Offset point) {
    if (tool.value != AnnotationTool.pen && !_highlighting) return;
    _active.value = (
      page: page,
      stroke: InkStroke(
        points: [point],
        color: _highlighting ? _highlighterColor.value.withValues(alpha: 0.4) : _penColor.value,
        width: strokeWidth.value,
        highlighter: _highlighting,
      ),
    );
  }

  void extendStroke(Offset point) {
    final active = _active.value;
    if (active == null) return;
    final points = active.stroke.points;
    // Ignora pontos quase iguais ao anterior para não inchar o arquivo.
    if ((points.last - point).distance < 0.0008) return;
    // Os pontos são mutados no lugar (criar uma lista por ponto gera
    // lixo à toa); `force` avisa quem escuta mesmo com o mesmo objeto.
    points.add(point);
    _active.set(active, force: true);
  }

  void endStroke() {
    final active = _active.value;
    _active.value = null;
    if (active == null) return;
    _apply(active.page, [...itemsFor(active.page), active.stroke]);
  }

  void cancelStroke() => _active.value = null;

  /// Borracha de traço: remove os itens que o ponteiro tocar.
  /// [radius] em pixels da página exibida.
  void eraseAt(int page, Offset point, double radius, Size pageSize) {
    final items = itemsFor(page);
    final remaining = [
      for (final item in items)
        if (!item.hitTest(point, radius, pageSize)) item,
    ];
    if (remaining.length != items.length) _apply(page, remaining);
  }

  void addText(int page, Offset position, String text) {
    if (text.trim().isEmpty) return;
    _apply(page, [
      ...itemsFor(page),
      TextNote(position: position, text: text, color: _penColor.value, fontSize: textSize),
    ]);
  }

  /// Item de texto no ponto, para permitir editar com duplo clique.
  TextNote? textAt(int page, Offset point, Size pageSize) {
    for (final item in itemsFor(page).reversed) {
      if (item is TextNote && item.hitTest(point, 4, pageSize)) return item;
    }
    return null;
  }

  void replaceText(int page, TextNote old, String newText) {
    final items = itemsFor(page);
    _apply(page, [
      for (final item in items)
        if (!identical(item, old))
          item
        else if (newText.trim().isNotEmpty)
          TextNote(position: old.position, text: newText, color: old.color, fontSize: old.fontSize),
    ]);
  }

  void clearPage(int page) {
    if (itemsFor(page).isEmpty) return;
    _apply(page, const []);
  }

  void undo() {
    final stack = _undo.value;
    if (stack.isEmpty) return;
    final change = stack.last;
    batch(() {
      _undo.value = stack.sublist(0, stack.length - 1);
      _redo.value = [..._redo.value, change];
      _setPage(change.page, change.before);
    });
    _changed();
  }

  void redo() {
    final stack = _redo.value;
    if (stack.isEmpty) return;
    final change = stack.last;
    batch(() {
      _redo.value = stack.sublist(0, stack.length - 1);
      _undo.value = [..._undo.value, change];
      _setPage(change.page, change.after);
    });
    _changed();
  }

  void _apply(int page, List<AnnotationItem> after) {
    final change = _Change(page, itemsFor(page), List.unmodifiable(after));
    final undo = [..._undo.value, change];
    if (undo.length > 200) undo.removeAt(0);
    batch(() {
      _undo.value = undo;
      _redo.value = const [];
      _setPage(page, after);
    });
    _changed();
  }

  void _setPage(int page, List<AnnotationItem> items) {
    final pages = {..._pages.value};
    if (items.isEmpty) {
      pages.remove(page);
    } else {
      pages[page] = List.unmodifiable(items);
    }
    _pages.value = Map.unmodifiable(pages);
  }

  void _changed() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, save);
  }

  // ---------- persistência ----------

  Future<void> load() async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final raw = (json['pages'] as Map<String, Object?>? ?? const {});
    final pages = <int, List<AnnotationItem>>{};
    for (final entry in raw.entries) {
      final items = [
        for (final raw in (entry.value as List)) AnnotationItem.fromJson((raw as Map).cast<String, Object?>()),
      ];
      if (items.isNotEmpty) pages[int.parse(entry.key)] = List.unmodifiable(items);
    }
    _pages.value = Map.unmodifiable(pages);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    final json = {
      'version': 1,
      'pages': {
        for (final entry in _pages.value.entries) '${entry.key}': [for (final item in entry.value) item.toJson()],
      },
    };
    // Escreve num temporário e renomeia: não corrompe se o app fechar no meio.
    final tmp = File('$filePath.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(filePath);
  }

  void dispose() => _saveTimer?.cancel();
}

class _Change {
  _Change(this.page, this.before, this.after);
  final int page;
  final List<AnnotationItem> before;
  final List<AnnotationItem> after;
}
