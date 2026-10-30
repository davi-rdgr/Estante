import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../annotations/annotation_controller.dart';
import '../annotations/annotation_layer.dart';
import '../annotations/annotation_models.dart';
import '../data/score.dart';
import '../data/score_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'viewer_controller.dart';

/// Leitor de partitura: uma ou duas páginas por vez (como numa estante),
/// virada de página por teclado/pedal/clique e anotações por cima.
///
/// É stateful só para ser dono do [ViewerController] (documento PDF,
/// anotações, zoom) e do foco dos atalhos; nada aqui chama setState.
/// O build em si não lê signals: quem reage é o SignalBuilder abaixo do
/// Theme e os SignalBuilders/SignalWidgets internos.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.score, required this.repository});

  final Score score;
  final ScoreRepository repository;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final _viewer = ViewerController(score: widget.score, repository: widget.repository);
  final _focusNode = FocusNode();

  AnnotationController get _annotations => _viewer.annotations;

  @override
  void initState() {
    super.initState();
    _viewer.open(
      isWideScreen: () {
        // Tela larga e partitura com várias páginas: começa em modo estante.
        final screen = MediaQuery.sizeOf(context);
        return screen.width / screen.height > 1.5;
      },
    );
  }

  @override
  void dispose() {
    _viewer.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// No modo leitura, clique no terço esquerdo volta e no direito avança.
  void _onTapUp(TapUpDetails details, double width) {
    if (_annotations.isEditing.value || _viewer.isZoomed) return;
    final x = details.localPosition.dx / width;
    if (x < 0.33) {
      _viewer.previous();
    } else if (x > 0.67) {
      _viewer.next();
    }
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    // Pedais de virar página (AirTurn, PageFlip etc.) costumam mandar setas ou PageUp/PageDown.
    const SingleActivator(LogicalKeyboardKey.arrowRight): _viewer.next,
    const SingleActivator(LogicalKeyboardKey.arrowDown): _viewer.next,
    const SingleActivator(LogicalKeyboardKey.pageDown): _viewer.next,
    const SingleActivator(LogicalKeyboardKey.space): _viewer.next,
    const SingleActivator(LogicalKeyboardKey.arrowLeft): _viewer.previous,
    const SingleActivator(LogicalKeyboardKey.arrowUp): _viewer.previous,
    const SingleActivator(LogicalKeyboardKey.pageUp): _viewer.previous,
    const SingleActivator(LogicalKeyboardKey.home): _viewer.first,
    const SingleActivator(LogicalKeyboardKey.end): _viewer.last,
    const SingleActivator(LogicalKeyboardKey.keyD): _viewer.toggleTwoPages,
    const SingleActivator(LogicalKeyboardKey.digit0): _viewer.resetZoom,
    const SingleActivator(LogicalKeyboardKey.keyP): () => _viewer.toggleTool(AnnotationTool.pen),
    const SingleActivator(LogicalKeyboardKey.keyH): () => _viewer.toggleTool(AnnotationTool.highlighter),
    const SingleActivator(LogicalKeyboardKey.keyE): () => _viewer.toggleTool(AnnotationTool.eraser),
    const SingleActivator(LogicalKeyboardKey.keyT): () => _viewer.toggleTool(AnnotationTool.text),
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _annotations.undo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): _annotations.redo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _annotations.redo,
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (_annotations.isEditing.value) {
        _viewer.toggleTool(null);
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
          // SignalBuilder e não Builder: o builder roda no build do próprio
          // elemento dele, então é ele quem precisa rastrear os signals lidos
          // em _buildAppBar/_buildBody (documento, página, edição).
          child: SignalBuilder(
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
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: context.tokens.readerChrome,
      toolbarHeight: 52,
      titleSpacing: 0,
      title: Text(widget.score.title, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
      // As ações ficam num SignalBuilder próprio: virar página ou trocar
      // de ferramenta reconstrói só a barra, não o leitor inteiro.
      actions: [
        SignalBuilder(
          builder: (context) {
            final editing = _annotations.isEditing.value;
            final twoPages = _viewer.twoPages.value;
            return Row(
              children: [
                IconButton(
                  tooltip: 'Página anterior (←)',
                  onPressed: _viewer.canGoPrevious.value ? _viewer.previous : null,
                  icon: const Icon(AppIcons.previous),
                ),
                Text(
                  _viewer.pageLabel.value,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  tooltip: 'Próxima página (→)',
                  onPressed: _viewer.canGoNext.value ? _viewer.next : null,
                  icon: const Icon(AppIcons.next),
                ),
                const SizedBox(height: 20, child: VerticalDivider(width: Space.xl)),
                IconButton(
                  tooltip: twoPages ? 'Uma página (D)' : 'Duas páginas (D)',
                  onPressed: _viewer.toggleTwoPages,
                  icon: Icon(twoPages ? AppIcons.singlePage : AppIcons.twoPages),
                ),
                IconButton(
                  tooltip: editing ? 'Sair da edição (Esc)' : 'Anotar (P)',
                  isSelected: editing,
                  onPressed: () => _annotations.tool.value = editing ? null : AnnotationTool.pen,
                  icon: const Icon(AppIcons.annotate),
                  selectedIcon: const Icon(AppIcons.annotate, fill: 1),
                ),
              ],
            );
          },
        ),
        const SizedBox(width: Space.md),
      ],
      // Lido direto no build (o AppBar precisa saber a altura do `bottom`):
      // só muda ao entrar/sair da edição, não a cada troca de ferramenta.
      bottom: _annotations.isEditing.value
          ? PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _AnnotationToolbar(controller: _annotations, onClearPages: _confirmClear),
            )
          : null,
    );
  }

  Future<void> _confirmClear() async {
    final pages = _viewer.visiblePages.value;
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
    // Tudo lido aqui, antes do LayoutBuilder: só leituras feitas direto
    // no build são rastreadas (o builder do LayoutBuilder roda no layout).
    final error = _viewer.error.value;
    if (error != null) {
      return Center(
        child: Text(
          'Não foi possível abrir o PDF.\n$error',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final doc = _viewer.document.value;
    if (doc == null) return const Center(child: CircularProgressIndicator());

    final pages = _viewer.visiblePages.value;
    final editing = _annotations.isEditing.value;

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTapUp: (d) => _onTapUp(d, constraints.maxWidth),
        child: InteractiveViewer(
          transformationController: _viewer.transform,
          minScale: 1,
          maxScale: 6,
          // Editando, arrastar desenha; o zoom continua com Ctrl+roda/pinça.
          panEnabled: !editing,
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

class _AnnotationToolbar extends SignalWidget {
  const _AnnotationToolbar({required this.controller, required this.onClearPages});

  final AnnotationController controller;
  final VoidCallback onClearPages;

  @override
  Widget build(BuildContext context) {
    final tool = controller.tool.value ?? AnnotationTool.pen;
    final color = controller.color.value;
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
            onSelectionChanged: (s) => controller.tool.value = s.first,
          ),
          if (usesColor) ...[
            const _ToolbarDivider(),
            for (final c in AnnotationController.palette)
              _ColorDot(color: c, selected: color == c, onTap: () => controller.setColor(c)),
          ],
          if (usesWidth) ...[
            const _ToolbarDivider(),
            const Icon(AppIcons.strokeWidth, size: 18),
            SizedBox(
              width: 120,
              child: Slider(
                value: controller.strokeWidth.value,
                min: tool == AnnotationTool.highlighter ? 0.008 : 0.001,
                max: tool == AnnotationTool.highlighter ? 0.04 : 0.012,
                onChanged: controller.setStrokeWidth,
              ),
            ),
          ],
          const _ToolbarDivider(),
          IconButton(
            tooltip: 'Desfazer (Ctrl+Z)',
            onPressed: controller.canUndo.value ? controller.undo : null,
            icon: const Icon(AppIcons.undo),
          ),
          IconButton(
            tooltip: 'Refazer (Ctrl+Y)',
            onPressed: controller.canRedo.value ? controller.redo : null,
            icon: const Icon(AppIcons.redo),
          ),
          IconButton(tooltip: 'Limpar página', onPressed: onClearPages, icon: const Icon(AppIcons.clearPage)),
        ],
      ),
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
