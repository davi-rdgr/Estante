import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/score.dart';
import '../data/score_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'score_details_dialog.dart';
import 'viewer_screen.dart';

enum ScoreSort {
  recent('Abertas recentemente'),
  title('Título'),
  composer('Compositor'),
  added('Adicionadas recentemente');

  const ScoreSort(this.label);
  final String label;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.repository});

  final ScoreRepository repository;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  ScoreSort _sort = ScoreSort.recent;
  bool _onlyFavorites = false;
  final Set<String> _tagFilter = {};
  bool _importing = false;

  ScoreRepository get _repo => widget.repository;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Score> _visibleScores() {
    final query = normalizeForSearch(_search.text.trim());
    final terms = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final list = _repo.scores.where((s) {
      if (_onlyFavorites && !s.favorite) return false;
      if (_tagFilter.isNotEmpty && !_tagFilter.every(s.tags.contains)) return false;
      final text = s.searchText;
      return terms.every(text.contains);
    }).toList();

    int byTitle(Score a, Score b) => normalizeForSearch(a.title).compareTo(normalizeForSearch(b.title));
    list.sort(switch (_sort) {
      ScoreSort.title => byTitle,
      ScoreSort.composer => (a, b) {
        final c = normalizeForSearch(a.composer).compareTo(normalizeForSearch(b.composer));
        return c != 0 ? c : byTitle(a, b);
      },
      ScoreSort.added => (a, b) => b.addedAt.compareTo(a.addedAt),
      ScoreSort.recent => (a, b) {
        final ta = a.lastOpenedAt ?? a.addedAt, tb = b.lastOpenedAt ?? b.addedAt;
        return tb.compareTo(ta);
      },
    });
    return list;
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Importar partituras',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final paths = [for (final f in files) ?f.path];
    if (paths.isEmpty || !mounted) return;

    setState(() => _importing = true);
    final imported = <Score>[];
    final failed = <String>[];
    for (final path in paths) {
      try {
        imported.add(await _repo.importPdf(path));
      } catch (_) {
        failed.add(path.split(RegExp(r'[\\/]')).last);
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);

    final messenger = ScaffoldMessenger.of(context);
    if (failed.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('Não consegui abrir: ${failed.join(', ')}')));
    } else if (imported.length > 1) {
      messenger.showSnackBar(SnackBar(content: Text('${imported.length} partituras importadas')));
    }
    // Importou uma só: já abre o formulário para preencher os dados.
    if (imported.length == 1) await _editDetails(imported.single);
  }

  Future<void> _editDetails(Score score) async {
    final updated = await showScoreDetailsDialog(context, score, knownTags: _repo.allTags);
    if (updated != null) _repo.update(updated);
  }

  Future<void> _delete(Score score) async {
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

  void _open(Score score) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerScreen(score: score, repository: _repo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _import,
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _repo,
          builder: (context, _) {
            final scores = _visibleScores();
            return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    Image.asset('assets/icon/estante_64.png', width: 24, height: 24),
                    const SizedBox(width: Space.md),
                    const Text('Estante'),
                  ],
                ),
                actions: [
                  SizedBox(width: 340, child: _buildSearchField()),
                  const SizedBox(width: Space.sm),
                  PopupMenuButton<ScoreSort>(
                    tooltip: 'Ordenar: ${_sort.label.toLowerCase()}',
                    icon: const Icon(AppIcons.sort),
                    initialValue: _sort,
                    onSelected: (s) => setState(() => _sort = s),
                    itemBuilder: (_) => [
                      for (final s in ScoreSort.values) PopupMenuItem(value: s, height: 36, child: Text(s.label)),
                    ],
                  ),
                  const SizedBox(width: Space.sm),
                  FilledButton.icon(
                    onPressed: _importing ? null : _import,
                    icon: _importing
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
                  if (_repo.scores.isNotEmpty) _buildFilters(),
                  Expanded(child: _repo.scores.isEmpty ? _buildEmptyLibrary() : _buildGrid(scores)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _search,
      focusNode: _searchFocus,
      onChanged: (_) => setState(() {}),
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Buscar por título, compositor ou tag',
        prefixIcon: const Icon(AppIcons.search, size: 18),
        suffixIcon: _search.text.isEmpty
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
                onPressed: () => setState(_search.clear),
              ),
        suffixIconConstraints: const BoxConstraints(minHeight: 32),
      ),
    );
  }

  Widget _buildFilters() {
    final tags = _repo.allTags;
    final colors = Theme.of(context).colorScheme;
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
              fill: _onlyFavorites ? 1 : 0,
              color: _onlyFavorites ? context.tokens.favorite : colors.onSurfaceVariant,
            ),
            label: const Text('Favoritas'),
            selected: _onlyFavorites,
            onSelected: (v) => setState(() => _onlyFavorites = v),
          ),
          for (final tag in tags)
            FilterChip(
              label: Text(tag),
              selected: _tagFilter.contains(tag),
              onSelected: (v) => setState(() => v ? _tagFilter.add(tag) : _tagFilter.remove(tag)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyLibrary() {
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
          FilledButton.icon(onPressed: _import, icon: const Icon(AppIcons.add), label: const Text('Importar PDF')),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Score> scores) {
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
          onOpen: () => _open(score),
          onToggleFavorite: () => _repo.toggleFavorite(score),
          onEdit: () => _editDetails(score),
          onDelete: () => _delete(score),
        );
      },
    );
  }
}

class _ScoreCard extends StatefulWidget {
  const _ScoreCard({
    super.key,
    required this.score,
    required this.pdfPath,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  final Score score;
  final String pdfPath;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ScoreCard> createState() => _ScoreCardState();
}

class _ScoreCardState extends State<_ScoreCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final score = widget.score;
    final details = [score.instrument, score.musicalKey].where((s) => s.isNotEmpty).join(', ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: _hover ? colors.outline : colors.outlineVariant),
        ),
        child: InkWell(
          onTap: widget.onOpen,
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
                        child: _Thumbnail(path: widget.pdfPath, pageCount: score.pageCount),
                      ),
                    ),
                    // Fita de favorita: como o marcador de uma edição encadernada.
                    if (score.favorite || _hover)
                      Positioned(
                        top: 0,
                        right: Space.sm,
                        child: IconButton(
                          tooltip: score.favorite ? 'Remover das favoritas' : 'Marcar como favorita',
                          onPressed: widget.onToggleFavorite,
                          style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(28, 32)),
                          icon: Icon(
                            AppIcons.favorite,
                            size: 24,
                            fill: score.favorite ? 1 : 0,
                            color: score.favorite ? context.tokens.favorite : colors.outline,
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
                        'open' => widget.onOpen(),
                        'edit' => widget.onEdit(),
                        'delete' => widget.onDelete(),
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
