import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'annotation_models.dart';

/// Estado das anotações de uma partitura: itens por página, ferramenta
/// atual, desfazer/refazer e salvamento automático em JSON.
class AnnotationController extends ChangeNotifier {
  AnnotationController({required this.filePath, this.autosaveDelay = const Duration(milliseconds: 800)});

  final String filePath;
  final Duration autosaveDelay;

  final Map<int, List<AnnotationItem>> _pages = {};
  final List<_Change> _undo = [];
  final List<_Change> _redo = [];
  Timer? _saveTimer;
  bool _dirty = false;

  // ---------- ferramenta ----------

  /// `null` = modo leitura (arrastar move a página, clique vira página).
  AnnotationTool? _tool;
  AnnotationTool? get tool => _tool;
  bool get isEditing => _tool != null;
  set tool(AnnotationTool? value) {
    _tool = value;
    notifyListeners();
  }

  static const palette = <Color>[
    Color(0xFF1E2533), // tinta
    Color(0xFFB3312A), // lápis vermelho
    Color(0xFF2B4C8C), // azul
    Color(0xFF2F7D4A), // verde
    Color(0xFFF0C02F), // amarelo (marca-texto)
    Color(0xFF7B3FA0), // roxo
  ];

  Color _penColor = palette[1];
  Color _highlighterColor = palette[4];
  Color get color => _tool == AnnotationTool.highlighter ? _highlighterColor : _penColor;
  set color(Color value) {
    if (_tool == AnnotationTool.highlighter) {
      _highlighterColor = value;
    } else {
      _penColor = value;
    }
    notifyListeners();
  }

  /// Espessura da caneta como fração da largura da página.
  double penWidth = 0.003;
  double highlighterWidth = 0.018;
  double textSize = 0.022;

  double get strokeWidth => _tool == AnnotationTool.highlighter ? highlighterWidth : penWidth;
  set strokeWidth(double value) {
    if (_tool == AnnotationTool.highlighter) {
      highlighterWidth = value;
    } else {
      penWidth = value;
    }
    notifyListeners();
  }

  // ---------- leitura ----------

  List<AnnotationItem> itemsFor(int page) => _pages[page] ?? const [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasAnyAnnotation => _pages.values.any((l) => l.isNotEmpty);

  /// Traço sendo desenhado agora (ainda não confirmado).
  InkStroke? activeStroke;
  int? activePage;

  // ---------- edição ----------

  void beginStroke(int page, Offset point) {
    if (_tool != AnnotationTool.pen && _tool != AnnotationTool.highlighter) return;
    activePage = page;
    activeStroke = InkStroke(
      points: [point],
      color: _tool == AnnotationTool.highlighter ? _highlighterColor.withValues(alpha: 0.4) : _penColor,
      width: strokeWidth,
      highlighter: _tool == AnnotationTool.highlighter,
    );
    notifyListeners();
  }

  void extendStroke(Offset point) {
    final stroke = activeStroke;
    if (stroke == null) return;
    // Ignora pontos quase iguais ao anterior para não inchar o arquivo.
    if ((stroke.points.last - point).distance < 0.0008) return;
    stroke.points.add(point);
    notifyListeners();
  }

  void endStroke() {
    final stroke = activeStroke;
    final page = activePage;
    activeStroke = null;
    activePage = null;
    if (stroke == null || page == null) return;
    _apply(page, [...itemsFor(page), stroke]);
  }

  void cancelStroke() {
    activeStroke = null;
    activePage = null;
    notifyListeners();
  }

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
    _apply(page, [...itemsFor(page), TextNote(position: position, text: text, color: _penColor, fontSize: textSize)]);
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
    if (_undo.isEmpty) return;
    final change = _undo.removeLast();
    _setPage(change.page, change.before);
    _redo.add(change);
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final change = _redo.removeLast();
    _setPage(change.page, change.after);
    _undo.add(change);
    _changed();
  }

  void _apply(int page, List<AnnotationItem> after) {
    final before = itemsFor(page);
    _undo.add(_Change(page, before, List.unmodifiable(after)));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    _setPage(page, after);
    _changed();
  }

  void _setPage(int page, List<AnnotationItem> items) {
    if (items.isEmpty) {
      _pages.remove(page);
    } else {
      _pages[page] = List.unmodifiable(items);
    }
  }

  void _changed() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, save);
    notifyListeners();
  }

  // ---------- persistência ----------

  Future<void> load() async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final pages = (json['pages'] as Map<String, Object?>? ?? const {});
    _pages.clear();
    for (final entry in pages.entries) {
      final items = [
        for (final raw in (entry.value as List)) AnnotationItem.fromJson((raw as Map).cast<String, Object?>()),
      ];
      if (items.isNotEmpty) _pages[int.parse(entry.key)] = List.unmodifiable(items);
    }
    notifyListeners();
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    final json = {
      'version': 1,
      'pages': {
        for (final entry in _pages.entries) '${entry.key}': [for (final item in entry.value) item.toJson()],
      },
    };
    // Escreve num temporário e renomeia: não corrompe se o app fechar no meio.
    final tmp = File('$filePath.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(filePath);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

class _Change {
  _Change(this.page, this.before, this.after);
  final int page;
  final List<AnnotationItem> before;
  final List<AnnotationItem> after;
}
