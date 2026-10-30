import 'dart:ui';

/// Todas as coordenadas são normalizadas em relação à página (0..1),
/// e espessuras/tamanhos em relação à largura da página. Assim as
/// anotações ficam no lugar certo independente de zoom ou resolução.
enum AnnotationTool { pen, highlighter, eraser, text }

sealed class AnnotationItem {
  const AnnotationItem();

  Map<String, Object?> toJson();

  /// Se o ponto (normalizado) encosta neste item, dentro do raio.
  bool hitTest(Offset point, double radius, Size pageSize);

  static AnnotationItem fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      'stroke' => InkStroke.fromJson(json),
      'text' => TextNote.fromJson(json),
      final type => throw FormatException('Tipo de anotação desconhecido: $type'),
    };
  }
}

class InkStroke extends AnnotationItem {
  const InkStroke({required this.points, required this.color, required this.width, this.highlighter = false});

  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlighter;

  @override
  Map<String, Object?> toJson() => {
    'type': 'stroke',
    'color': color.toARGB32(),
    'width': width,
    'highlighter': highlighter,
    // Lista plana [x0, y0, x1, y1, ...] com 4 casas: arquivo bem menor.
    'points': [
      for (final pt in points) ...[_round(pt.dx), _round(pt.dy)],
    ],
  };

  factory InkStroke.fromJson(Map<String, Object?> json) {
    final flat = (json['points'] as List).cast<num>();
    return InkStroke(
      color: Color(json['color'] as int),
      width: (json['width'] as num).toDouble(),
      highlighter: json['highlighter'] as bool? ?? false,
      points: [for (var i = 0; i + 1 < flat.length; i += 2) Offset(flat[i].toDouble(), flat[i + 1].toDouble())],
    );
  }

  @override
  bool hitTest(Offset point, double radius, Size pageSize) {
    // Compara em pixels da página, senão o raio fica distorcido
    // (a página não é quadrada).
    Offset px(Offset o) => Offset(o.dx * pageSize.width, o.dy * pageSize.height);
    final target = px(point);
    final tolerance = radius + width * pageSize.width / 2;
    if (points.length == 1) return (px(points.first) - target).distance <= tolerance;
    for (var i = 0; i < points.length - 1; i++) {
      if (_distanceToSegment(target, px(points[i]), px(points[i + 1])) <= tolerance) return true;
    }
    return false;
  }
}

class TextNote extends AnnotationItem {
  const TextNote({required this.position, required this.text, required this.color, required this.fontSize});

  /// Canto superior esquerdo do texto.
  final Offset position;
  final String text;
  final Color color;
  final double fontSize;

  @override
  Map<String, Object?> toJson() => {
    'type': 'text',
    'x': _round(position.dx),
    'y': _round(position.dy),
    'text': text,
    'color': color.toARGB32(),
    'fontSize': fontSize,
  };

  factory TextNote.fromJson(Map<String, Object?> json) => TextNote(
    position: Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
    text: json['text'] as String,
    color: Color(json['color'] as int),
    fontSize: (json['fontSize'] as num).toDouble(),
  );

  /// Retângulo aproximado ocupado pelo texto, em coordenadas normalizadas.
  Rect approximateBounds(Size pageSize) {
    final lines = text.split('\n');
    final longest = lines.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final fontPx = fontSize * pageSize.width;
    final w = longest * fontPx * 0.6 / pageSize.width;
    final h = lines.length * fontPx * 1.3 / pageSize.height;
    return Rect.fromLTWH(position.dx, position.dy, w, h);
  }

  @override
  bool hitTest(Offset point, double radius, Size pageSize) {
    final r = approximateBounds(pageSize).inflate(radius / pageSize.width);
    return r.contains(point);
  }
}

double _round(double v) => (v * 10000).roundToDouble() / 10000;

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
