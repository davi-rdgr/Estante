import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'annotation_controller.dart';
import 'annotation_models.dart';

/// Camada transparente por cima de uma página do PDF. Desenha as
/// anotações e, no modo edição, captura o ponteiro para desenhar.
///
/// Usa [Listener] (eventos crus) em vez de GestureDetector para não
/// disputar a arena de gestos com o zoom do InteractiveViewer.
///
/// O build só depende da ferramenta; traços novos não reconstroem nada,
/// o [AnnotationPainter] repinta direto quando os signals mudam.
class AnnotationLayer extends SignalWidget {
  const AnnotationLayer({super.key, required this.controller, required this.pageNumber});

  final AnnotationController controller;
  final int pageNumber;

  static const _eraserRadius = 10.0;

  AnnotationController get _c => controller;

  Offset _normalize(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  void _onDown(PointerDownEvent e, Size size) {
    if (_c.activePointer != null) return; // ignora segundo dedo
    final point = _normalize(e.localPosition, size);
    final secondary = e.buttons & kSecondaryMouseButton != 0;
    final eraserTip = e.kind == PointerDeviceKind.invertedStylus;

    if (secondary || eraserTip || _c.tool.value == AnnotationTool.eraser) {
      _c.activePointer = e.pointer;
      _c.erasing = true;
      _c.lastErase = e.localPosition;
      _c.eraseAt(pageNumber, point, _eraserRadius, size);
      return;
    }
    if (e.buttons & kPrimaryButton == 0) return;

    switch (_c.tool.value) {
      case AnnotationTool.pen || AnnotationTool.highlighter:
        _c.activePointer = e.pointer;
        _c.beginStroke(pageNumber, point);
      case AnnotationTool.text:
        _c.activePointer = e.pointer;
      case AnnotationTool.eraser || null:
        break;
    }
  }

  void _onMove(PointerMoveEvent e, Size size) {
    if (e.pointer != _c.activePointer) return;
    final point = _normalize(e.localPosition, size);
    if (_c.erasing) {
      _eraseAlong(_c.lastErase ?? e.localPosition, e.localPosition, size);
      _c.lastErase = e.localPosition;
    } else {
      _c.extendStroke(point);
    }
  }

  /// Movimentos rápidos geram pontos distantes: testa o caminho inteiro
  /// entre eles para a borracha não "pular" traços.
  void _eraseAlong(Offset from, Offset to, Size size) {
    final steps = math.max(1, ((to - from).distance / (_eraserRadius / 2)).ceil());
    for (var i = 1; i <= steps; i++) {
      final local = Offset.lerp(from, to, i / steps)!;
      _c.eraseAt(pageNumber, _normalize(local, size), _eraserRadius, size);
    }
  }

  Future<void> _onUp(BuildContext context, PointerUpEvent e, Size size) async {
    if (e.pointer != _c.activePointer) return;
    _c.activePointer = null;
    if (_c.erasing) {
      _c.erasing = false;
      return;
    }
    if (_c.tool.value == AnnotationTool.text) {
      await _editText(context, _normalize(e.localPosition, size), size);
      return;
    }
    _c.endStroke();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _c.activePointer) return;
    _c.activePointer = null;
    _c.erasing = false;
    _c.cancelStroke();
  }

  Future<void> _editText(BuildContext context, Offset point, Size size) async {
    final existing = _c.textAt(pageNumber, point, size);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _TextDialog(initial: existing?.text ?? ''),
    );
    if (text == null || !context.mounted) return;
    if (existing != null) {
      _c.replaceText(pageNumber, existing, text);
    } else {
      _c.addText(pageNumber, point, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lido aqui, fora do LayoutBuilder: só o que é lido direto no build
    // é rastreado (o builder do LayoutBuilder roda depois, no layout).
    final tool = _c.tool.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final painter = CustomPaint(
          size: size,
          painter: AnnotationPainter(controller: _c, pageNumber: pageNumber),
        );
        if (tool == null) return painter;
        return MouseRegion(
          cursor: switch (tool) {
            AnnotationTool.text => SystemMouseCursors.text,
            AnnotationTool.eraser => SystemMouseCursors.disappearing,
            _ => SystemMouseCursors.precise,
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _onDown(e, size),
            onPointerMove: (e) => _onMove(e, size),
            onPointerUp: (e) => _onUp(context, e, size),
            onPointerCancel: _onCancel,
            child: painter,
          ),
        );
      },
    );
  }
}

/// Pinta as anotações de uma página. Escuta os signals de itens e do
/// traço ativo como `repaint`: cada ponto novo só repinta, sem rebuild.
class AnnotationPainter extends CustomPainter {
  AnnotationPainter({required this.controller, required this.pageNumber})
    : super(repaint: Listenable.merge([controller.pages, controller.activeStroke]));

  final AnnotationController controller;
  final int pageNumber;

  @override
  void paint(Canvas canvas, Size size) {
    for (final item in controller.itemsFor(pageNumber)) {
      _paintItem(canvas, size, item);
    }
    final active = controller.activeStroke.value;
    if (active != null && active.page == pageNumber) _paintItem(canvas, size, active.stroke);
  }

  void _paintItem(Canvas canvas, Size size, AnnotationItem item) {
    switch (item) {
      case InkStroke():
        _paintStroke(canvas, size, item);
      case TextNote():
        _paintText(canvas, size, item);
    }
  }

  void _paintStroke(Canvas canvas, Size size, InkStroke stroke) {
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width * size.width
      ..style = PaintingStyle.stroke
      ..strokeCap = stroke.highlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      // Multiply deixa a tinta preta da partitura visível sob o marca-texto.
      ..blendMode = stroke.highlighter ? BlendMode.multiply : BlendMode.srcOver;

    Offset px(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
    final pts = stroke.points;
    if (pts.length == 1) {
      canvas.drawCircle(px(pts.first), paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }
    // Curvas quadráticas entre pontos médios: traço mais suave.
    final path = Path()..moveTo(px(pts.first).dx, px(pts.first).dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final p0 = px(pts[i]);
      final mid = (p0 + px(pts[i + 1])) / 2;
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(px(pts.last).dx, px(pts.last).dy);
    canvas.drawPath(path, paint);
  }

  void _paintText(Canvas canvas, Size size, TextNote note) {
    final painter = TextPainter(
      text: TextSpan(
        text: note.text,
        style: TextStyle(
          color: note.color,
          fontSize: note.fontSize * size.width,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(note.position.dx * size.width, note.position.dy * size.height));
    painter.dispose();
  }

  // Mudanças de conteúdo chegam pelo `repaint`; aqui só importa se é outra página.
  @override
  bool shouldRepaint(AnnotationPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) || pageNumber != oldDelegate.pageNumber;
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.initial});
  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'Adicionar texto' : 'Editar texto'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'ex.: rit., 1-3-5, respirar aqui'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        if (widget.initial.isNotEmpty)
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Apagar')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('OK')),
      ],
    );
  }
}
