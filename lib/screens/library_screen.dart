import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/score.dart';
import '../data/score_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'library_controller.dart';
import 'score_details_dialog.dart';
import 'viewer_screen.dart';

/// Biblioteca: grade de partituras com busca, filtros e ordenação.
/// O estado fica no [LibraryController]; aqui é só build.
class LibraryScreen extends SignalWidget {
  const LibraryScreen({super.key, required this.controller});

  final LibraryController controller;

  LibraryController get _c => controller;
  ScoreRepository get _repo => controller.repository;

  Future<void> _import(BuildContext context) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Importar partituras',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final paths = [for (final f in files) ?f.path];
    if (paths.isEmpty || !context.mounted) return;

    _c.importing.value = true;
    final imported = <Score>[];
    final failed = <String>[];
    for (final path in paths) {
      try {
        imported.add(await _repo.importPdf(path));
      } catch (_) {
        failed.add(path.split(RegExp(r'[\\/]')).last);
      }
    }
    _c.importing.value = false;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (failed.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('Não consegui abrir: ${failed.join(', ')}')));
    } else if (imported.length > 1) {
      messenger.showSnackBar(SnackBar(content: Text('${imported.length} partituras importadas')));
    }
    // Importou uma só: já abre o formulário para preencher os dados.
    if (imported.length == 1) await _editDetails(context, imported.single);
  }

  Future<void> _editDetails(BuildContext context, Score score) async {
    final updated = await showScoreDetailsDialog(context, score, knownTags: _repo.allTags.value);
    if (updated != null) _repo.update(updated);
  }

  Future<void> _delete(BuildContext context, Score score) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir partitura?'),
        content: Text('"${score.title}" e todas as suas anotações serão removidas da biblioteca.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) await _repo.delete(score);
  }

  void _open(BuildContext context, Score score) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerScreen(score: score, repository: _repo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sort = _c.sort.value;
    final importing = _c.importing.value;
    final hasScores = _repo.scores.value.isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _c.searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => _import(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset('assets/icon/estante_64.png', width: 24, height: 24),
                const SizedBox(width: Space.md),
                const Text('Estante'),
              ],
            ),
            actions: [
              SizedBox(width: 340, child: _buildSearchField(context)),
              const SizedBox(width: Space.sm),
              PopupMenuButton<ScoreSort>(
                tooltip: 'Ordenar: ${sort.label.toLowerCase()}',
                icon: const Icon(AppIcons.sort),
                initialValue: sort,
                onSelected: (s) => _c.sort.value = s,
                itemBuilder: (_) => [
                  for (final s in ScoreSort.values) PopupMenuItem(value: s, height: 36, child: Text(s.label)),
                ],
              ),
              const SizedBox(width: Space.sm),
              FilledButton.icon(
                onPressed: importing ? null : () => _import(context),
                icon: importing
                    ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(AppIcons.add),
                label: const Text('Importar PDF'),
              ),
              const SizedBox(width: Space.xl),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasScores) _buildFilters(context),
              Expanded(child: hasScores ? _buildGrid(context, _c.visibleScores.value) : _buildEmptyLibrary(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _c.searchField,
      focusNode: _c.searchFocus,
      onChanged: (v) => _c.query.value = v,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Buscar por título, compositor ou tag',
        prefixIcon: const Icon(AppIcons.search, size: 18),
        suffixIcon: _c.query.value.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(right: Space.md),
                child: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text('Ctrl+F', style: Theme.of(context).textTheme.labelSmall),
                ),
              )
            : IconButton(
                tooltip: 'Limpar busca',
                iconSize: 16,
                icon: const Icon(AppIcons.clear),
                onPressed: _c.clearSearch,
              ),
        suffixIconConstraints: const BoxConstraints(minHeight: 32),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final onlyFavorites = _c.onlyFavorites.value;
    final selectedTags = _c.tagFilter.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, Space.sm),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          FilterChip(
            avatar: Icon(
              AppIcons.favorite,
              size: 16,
              fill: onlyFavorites ? 1 : 0,
              color: onlyFavorites ? context.tokens.favorite : colors.onSurfaceVariant,
            ),
            label: const Text('Favoritas'),
            selected: onlyFavorites,
            onSelected: (v) => _c.onlyFavorites.value = v,
          ),
          for (final tag in _repo.allTags.value)
            FilterChip(label: Text(tag), selected: selectedTags.contains(tag), onSelected: (v) => _c.toggleTag(tag, v)),
        ],
      ),
    );
  }

  Widget _buildEmptyLibrary(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.library, size: 48, weight: 200, color: theme.colorScheme.outline),
          const SizedBox(height: Space.lg),
          Text('Nenhuma partitura ainda', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.xs),
          Text('Importe seus PDFs para montar a biblioteca.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: Space.xl),
          FilledButton.icon(
            onPressed: () => _import(context),
            icon: const Icon(AppIcons.add),
            label: const Text('Importar PDF'),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<Score> scores) {
    if (scores.isEmpty) {
      return Center(child: Text('Nada encontrado com esses filtros.', style: Theme.of(context).textTheme.bodyMedium));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xl),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 196,
        childAspectRatio: 0.6,
        crossAxisSpacing: Space.lg,
        mainAxisSpacing: Space.lg,
      ),
      itemCount: scores.length,
      itemBuilder: (context, i) {
        final score = scores[i];
        return _ScoreCard(
          key: ValueKey(score.id),
          score: score,
          pdfPath: _repo.storage.pdfPath(score.fileName),
          hoveredId: _c.hoveredId,
          onOpen: () => _open(context, score),
          onToggleFavorite: () => _repo.toggleFavorite(score),
          onEdit: () => _editDetails(context, score),
          onDelete: () => _delete(context, score),
        );
      },
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    super.key,
    required this.score,
    required this.pdfPath,
    required this.hoveredId,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  final Score score;
  final String pdfPath;
  final FlutterSignal<String?> hoveredId;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  bool get _hover => hoveredId.value == score.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details = [score.instrument, score.musicalKey].where((s) => s.isNotEmpty).join(', ');

    // Só a borda e a fita dependem do hover, e ficam em SignalBuilders.
    // O conteúdo (com a miniatura do PDF) é a mesma instância entre esses
    // rebuilds, então o Flutter nem chega a reconstruí-lo.
    final content = InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: colors.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md),
                    child: _Thumbnail(path: pdfPath, pageCount: score.pageCount),
                  ),
                ),
                // Fita de favorita: como o marcador de uma edição encadernada.
                Positioned(
                  top: 0,
                  right: Space.sm,
                  child: SignalBuilder(
                    builder: (context) => Visibility.maintain(
                      visible: score.favorite || _hover,
                      child: IconButton(
                        tooltip: score.favorite ? 'Remover das favoritas' : 'Marcar como favorita',
                        onPressed: onToggleFavorite,
                        style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(28, 32)),
                        icon: Icon(
                          AppIcons.favorite,
                          size: 24,
                          fill: score.favorite ? 1 : 0,
                          color: score.favorite ? context.tokens.favorite : colors.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        score.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (score.composer.isNotEmpty)
                        Text(
                          score.composer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      Text(
                        [
                          if (details.isNotEmpty) details,
                          '${score.pageCount} ${score.pageCount == 1 ? 'página' : 'páginas'}',
                        ].join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mais opções',
                  icon: const Icon(AppIcons.more),
                  style: IconButton.styleFrom(minimumSize: const Size(28, 28), padding: EdgeInsets.zero),
                  onSelected: (v) => switch (v) {
                    'open' => onOpen(),
                    'edit' => onEdit(),
                    'delete' => onDelete(),
                    _ => null,
                  },
                  itemBuilder: (context) => [
                    _menuItem('open', AppIcons.open, 'Abrir'),
                    _menuItem('edit', AppIcons.editInfo, 'Editar informações'),
                    const PopupMenuDivider(height: 9),
                    _menuItem('delete', AppIcons.delete, 'Excluir', color: colors.error),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => hoveredId.value = score.id,
      // Só limpa se ainda for este card: o onEnter do vizinho pode chegar antes.
      onExit: (_) {
        if (hoveredId.value == score.id) hoveredId.value = null;
      },
      child: SignalBuilder(
        builder: (context) => Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
            side: BorderSide(color: _hover ? colors.outline : colors.outlineVariant),
          ),
          child: content,
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color? color}) {
    return PopupMenuItem(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.md),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }
}

/// Miniatura da primeira página. Partituras com mais de uma página
/// ganham folhas deslocadas por trás, como uma pilha de papel.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path, required this.pageCount});

  final String path;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sheets = pageCount.clamp(1, 3) - 1;
    final edge = BoxDecoration(
      color: Colors.white,
      border: Border.all(color: colors.outlineVariant, width: 0.5),
    );

    return PdfDocumentViewBuilder.file(
      path,
      builder: (context, document) => PdfPageView(
        document: document,
        pageNumber: 1,
        maximumDpi: 72,
        decorationBuilder: (context, pageSize, page, image) => Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(right: sheets * 3.0, bottom: sheets * 3.0),
            child: AspectRatio(
              aspectRatio: pageSize.width / pageSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = sheets; i >= 1; i--)
                    Positioned.fill(
                      left: i * 3.0,
                      top: i * 3.0,
                      right: -i * 3.0,
                      bottom: -i * 3.0,
                      child: DecoratedBox(decoration: edge),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: edge.copyWith(
                        boxShadow: const [BoxShadow(color: Color(0x1F1E2533), blurRadius: 3, offset: Offset(0, 1))],
                      ),
                      child: image,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
