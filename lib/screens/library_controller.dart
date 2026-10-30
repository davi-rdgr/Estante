import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/score.dart';
import '../data/score_repository.dart';

enum ScoreSort {
  recent('Abertas recentemente'),
  title('Título'),
  composer('Compositor'),
  added('Adicionadas recentemente');

  const ScoreSort(this.label);
  final String label;
}

/// Estado da tela da biblioteca: busca, filtros, ordenação e o que está
/// sob o mouse. Vive o app inteiro (a biblioteca é a tela inicial), por
/// isso é criado no `main` e a [LibraryScreen] pode ser stateless.
class LibraryController {
  LibraryController(this.repository);

  final ScoreRepository repository;

  /// O campo de busca precisa de um controller próprio; o texto em si
  /// vai para [query] pelo `onChanged`.
  final searchField = TextEditingController();
  final searchFocus = FocusNode();

  final query = signal('');
  final sort = signal(ScoreSort.recent);
  final onlyFavorites = signal(false);
  final tagFilter = signal<Set<String>>(const {});
  final importing = signal(false);

  /// Id da partitura sob o mouse (destaca o card e mostra a fita de favorita).
  final hoveredId = signal<String?>(null);

  void toggleTag(String tag, bool selected) =>
      tagFilter.value = selected ? {...tagFilter.value, tag} : ({...tagFilter.value}..remove(tag));

  void clearSearch() {
    searchField.clear();
    query.value = '';
  }

  /// Partituras que passam na busca e nos filtros, já ordenadas.
  late final FlutterReadonlySignal<List<Score>> visibleScores = computed(() {
    final terms = normalizeForSearch(query.value.trim()).split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final favoritesOnly = onlyFavorites.value;
    final tags = tagFilter.value;
    final list = repository.scores.value.where((s) {
      if (favoritesOnly && !s.favorite) return false;
      if (tags.isNotEmpty && !tags.every(s.tags.contains)) return false;
      final text = s.searchText;
      return terms.every(text.contains);
    }).toList();

    int byTitle(Score a, Score b) => normalizeForSearch(a.title).compareTo(normalizeForSearch(b.title));
    list.sort(switch (sort.value) {
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
    return List.unmodifiable(list);
  });

  void dispose() {
    searchField.dispose();
    searchFocus.dispose();
  }
}
