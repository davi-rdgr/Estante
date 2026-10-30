import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../annotations/annotation_controller.dart';
import '../annotations/annotation_layer.dart';
import '../annotations/annotation_models.dart';
import '../data/score.dart';
import '../data/score_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Leitor de partitura: uma ou duas páginas por vez (como numa estante),
/// virada de página por teclado/pedal/clique e anotações por cima.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.score, required this.repository});

  final Score score;
  final ScoreRepository repository;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  PdfDocument? _document;
  Object? _error;
  late final AnnotationController _annotations;
  final _transform = TransformationController();
  final _focusNode = FocusNode();

  late int _page = widget.score.lastPage;
  bool _twoPages = false;

  int get _pageCount => _document?.pages.length ?? 0;
  int get _step => _twoPages ? 2 : 1;

  @override
  void initState() {
    super.initState();
    _annotations = AnnotationController(filePath: widget.repository.storage.annotationsPath(widget.score.id));
    _open();
  }

  Future<void> _open() async {
    try {
      final path = widget.repository.storage.pdfPath(widget.score.fileName);
      final doc = await PdfDocument.openFile(path);
      await _annotations.load();
      if (!mounted) {
        await doc.dispose();
        return;
      }
      setState(() {
        _document = doc;
        _page = _page.clamp(1, math.max(1, doc.pages.length));
        // Tela larga e partitura com várias páginas: começa em modo estante.
        final screen = MediaQuery.sizeOf(context);
        _twoPages = doc.pages.length > 1 && screen.width / screen.height > 1.5;
      });
      widget.repository.markOpened(widget.score, page: _page);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _annotations.save();
    _annotations.dispose();
    if (_document != null) {
      // Fora do dispose: atualizar o repositório notifica a biblioteca,
      // e não se pode reconstruir widgets enquanto a árvore está travada.
      final repo = widget.repository, score = widget.score, page = _page;
      Future.microtask(() => repo.markOpened(score, page: page));
      _document!.dispose();
    }
    _transform.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------- navegação ----------

  void _goTo(int page) {
    if (_pageCount == 0) return;
    final target = page.clamp(1, _pageCount);
    if (target == _page) return;
    setState(() {
      _page = target;
      _transform.value = Matrix4.identity();
    });
  }

  void _next() {
    if (_page + _step <= _pageCount) _goTo(_page + _step);
  }

  void _previous() => _goTo(_page - _step);

  void _toggleTwoPages() => setState(() => _twoPages = !_twoPages);

  void _setTool(AnnotationTool? tool) {
    _annotations.tool = _annotations.tool == tool ? null : tool;
    setState(() {});
  }

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  /// No modo leitura, clique no terço esquerdo volta e no direito avança.
  void _onTapUp(TapUpDetails details, double width) {
    if (_annotations.isEditing || _isZoomed) return;
    final x = details.localPosition.dx / width;
    if (x < 0.33) {
      _previous();
    } else if (x > 0.67) {
      _next();
    }
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    // Pedais de virar página (AirTurn, PageFlip etc.) costumam mandar setas ou PageUp/PageDown.
    const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
    const SingleActivator(LogicalKeyboardKey.arrowDown): _next,
    const SingleActivator(LogicalKeyboardKey.pageDown): _next,
    const SingleActivator(LogicalKeyboardKey.space): _next,
    const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
    const SingleActivator(LogicalKeyboardKey.arrowUp): _previous,
    const SingleActivator(LogicalKeyboardKey.pageUp): _previous,
    const SingleActivator(LogicalKeyboardKey.home): () => _goTo(1),
    const SingleActivator(LogicalKeyboardKey.end): () => _goTo(_pageCount),
    const SingleActivator(LogicalKeyboardKey.keyD): _toggleTwoPages,
    const SingleActivator(LogicalKeyboardKey.digit0): () => setState(() => _transform.value = Matrix4.identity()),
    const SingleActivator(LogicalKeyboardKey.keyP): () => _setTool(AnnotationTool.pen),
    const SingleActivator(LogicalKeyboardKey.keyH): () => _setTool(AnnotationTool.highlighter),
    const SingleActivator(LogicalKeyboardKey.keyE): () => _setTool(AnnotationTool.eraser),
    const SingleActivator(LogicalKeyboardKey.keyT): () => _setTool(AnnotationTool.text),
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _annotations.undo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): _annotations.redo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _annotations.redo,
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (_annotations.isEditing) {
        _setTool(null);
      } else {
        Navigator.maybePop(context);
      }
    },
  };

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        // O leitor é sempre escuro: a página branca é a única coisa clara na tela.
        child: Theme(
          data: AppTheme.dark,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.tokens.readerBackground,
              appBar: _buildAppBar(context),
              body: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final editing = _annotations.isEditing;
    final lastShown = math.min(_page + _step - 1, _pageCount);
    final pageLabel = _pageCount == 0
        ? ''
        : lastShown > _page
        ? '$_page–$lastShown / $_pageCount'
        : '$_page / $_pageCount';

    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: context.tokens.readerChrome,
      toolbarHeight: 52,
      titleSpacing: 0,
      title: Text(widget.score.title, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
      actions: [
        IconButton(
          tooltip: 'Página anterior (←)',
          onPressed: _page > 1 ? _previous : null,
          icon: const Icon(AppIcons.previous),
        ),
        Center(
          child: Text(
            pageLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Próxima página (→)',
          onPressed: _page + _step <= _pageCount ? _next : null,
          icon: const Icon(AppIcons.next),
        ),
        const VerticalDivider(indent: 16, endIndent: 16, width: Space.xl),
        IconButton(
          tooltip: _twoPages ? 'Uma página (D)' : 'Duas páginas (D)',
          onPressed: _toggleTwoPages,
          icon: Icon(_twoPages ? AppIcons.singlePage : AppIcons.twoPages),
        ),
        IconButton(
          tooltip: editing ? 'Sair da edição (Esc)' : 'Anotar (P)',
          isSelected: editing,
          onPressed: () => _setTool(editing ? null : AnnotationTool.pen),
          icon: const Icon(AppIcons.annotate),
          selectedIcon: const Icon(AppIcons.annotate, fill: 1),
        ),
        const SizedBox(width: Space.md),
      ],
      bottom: editing
          ? PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _AnnotationToolbar(
                controller: _annotations,
                onToolChanged: (t) => setState(() => _annotations.tool = t),
                onClearPages: _confirmClear,
              ),
            )
          : null,
    );
  }

  Future<void> _confirmClear() async {
    final pages = [for (var p = _page; p < _page + _step && p <= _pageCount; p++) p];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar anotações?'),
        content: Text(
          pages.length == 1
              ? 'Remove todas as anotações da página ${pages.first}. Dá pra desfazer com Ctrl+Z.'
              : 'Remove todas as anotações das páginas ${pages.join(' e ')}. Dá pra desfazer com Ctrl+Z.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Limpar')),
        ],
      ),
    );
    if (ok == true) {
      for (final p in pages) {
        _annotations.clearPage(p);
      }
    }
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(
          'Não foi possível abrir o PDF.\n$_error',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final doc = _document;
    if (doc == null) return const Center(child: CircularProgressIndicator());

    final pages = [for (var p = _page; p < _page + _step && p <= _pageCount; p++) p];

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: _annotations,
          builder: (context, _) => GestureDetector(
            onTapUp: (d) => _onTapUp(d, constraints.maxWidth),
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 6,
              // Editando, arrastar desenha; o zoom continua com Ctrl+roda/pinça.
              panEnabled: !_annotations.isEditing,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Row(
                    children: [
                      for (final (i, p) in pages.indexed) ...[
                        if (i > 0) const SizedBox(width: Space.md),
                        Expanded(
                          child: _PageWithAnnotations(
                            key: ValueKey(p),
                            document: doc,
                            pageNumber: p,
                            controller: _annotations,
                            // Página da esquerda encosta à direita e vice-versa (como livro aberto).
                            alignment: pages.length == 1
                                ? Alignment.center
                                : i == 0
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageWithAnnotations extends StatelessWidget {
  const _PageWithAnnotations({
    super.key,
    required this.document,
    required this.pageNumber,
    required this.controller,
    required this.alignment,
  });

  final PdfDocument document;
  final int pageNumber;
  final AnnotationController controller;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return PdfPageView(
      document: document,
      pageNumber: pageNumber,
      // Renderiza com o dobro da resolução da tela para o zoom não ficar borrado.
      pageSizeCallback: (biggest, page, rotation) {
        final scale = math.min(biggest.width / page.width, biggest.height / page.height) * 2;
        final capped = math.min(scale, 400 / 72);
        return Size(page.width * capped, page.height * capped);
      },
      decorationBuilder: (context, pageSize, page, image) => Align(
        alignment: alignment,
        child: AspectRatio(
          aspectRatio: pageSize.width / pageSize.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: context.tokens.pageShadow, blurRadius: 12, offset: const Offset(0, 3))],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ?image,
                AnnotationLayer(controller: controller, pageNumber: pageNumber),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnotationToolbar extends StatelessWidget {
  const _AnnotationToolbar({required this.controller, required this.onToolChanged, required this.onClearPages});

  final AnnotationController controller;
  final ValueChanged<AnnotationTool> onToolChanged;
  final VoidCallback onClearPages;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tool = controller.tool ?? AnnotationTool.pen;
        final usesColor = tool != AnnotationTool.eraser;
        final usesWidth = tool == AnnotationTool.pen || tool == AnnotationTool.highlighter;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
          child: Row(
            children: [
              SegmentedButton<AnnotationTool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: AnnotationTool.pen, icon: Icon(AppIcons.pen), tooltip: 'Caneta (P)'),
                  ButtonSegment(
                    value: AnnotationTool.highlighter,
                    icon: Icon(AppIcons.highlighter),
                    tooltip: 'Marca-texto (H)',
                  ),
                  ButtonSegment(
                    value: AnnotationTool.text,
                    icon: Icon(AppIcons.text),
                    tooltip: 'Texto (T) — clique num texto para editar',
                  ),
                  ButtonSegment(
                    value: AnnotationTool.eraser,
                    icon: Icon(AppIcons.eraser),
                    tooltip: 'Borracha (E) — ou botão direito do mouse',
                  ),
                ],
                selected: {tool},
                onSelectionChanged: (s) => onToolChanged(s.first),
              ),
              if (usesColor) ...[
                const _ToolbarDivider(),
                for (final c in AnnotationController.palette)
                  _ColorDot(color: c, selected: controller.color == c, onTap: () => controller.color = c),
              ],
              if (usesWidth) ...[
                const _ToolbarDivider(),
                const Icon(AppIcons.strokeWidth, size: 18),
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: controller.strokeWidth,
                    min: tool == AnnotationTool.highlighter ? 0.008 : 0.001,
                    max: tool == AnnotationTool.highlighter ? 0.04 : 0.012,
                    onChanged: (v) => controller.strokeWidth = v,
                  ),
                ),
              ],
              const _ToolbarDivider(),
              IconButton(
                tooltip: 'Desfazer (Ctrl+Z)',
                onPressed: controller.canUndo ? controller.undo : null,
                icon: const Icon(AppIcons.undo),
              ),
              IconButton(
                tooltip: 'Refazer (Ctrl+Y)',
                onPressed: controller.canRedo ? controller.redo : null,
                icon: const Icon(AppIcons.redo),
              ),
              IconButton(tooltip: 'Limpar página', onPressed: onClearPages, icon: const Icon(AppIcons.clearPage)),
            ],
          ),
        );
      },
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 24, child: VerticalDivider(width: Space.xl));
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 26,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? ring : Colors.transparent, width: 2),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
          ),
        ),
      ),
    );
  }
}
