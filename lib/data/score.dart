import 'dart:convert';

/// Uma partitura da biblioteca. O PDF fica copiado na pasta do app
/// (ver [AppStorage]); aqui guardamos só o nome do arquivo.
class Score {
  const Score({
    required this.id,
    required this.title,
    required this.fileName,
    required this.addedAt,
    this.composer = '',
    this.instrument = '',
    this.musicalKey = '',
    this.tags = const [],
    this.favorite = false,
    this.originalName,
    this.pageCount = 0,
    this.lastPage = 1,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String composer;
  final String instrument;
  final String musicalKey;
  final List<String> tags;
  final bool favorite;
  final String fileName;
  final String? originalName;
  final int pageCount;
  final int lastPage;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;

  Score copyWith({
    String? title,
    String? composer,
    String? instrument,
    String? musicalKey,
    List<String>? tags,
    bool? favorite,
    int? pageCount,
    int? lastPage,
    DateTime? lastOpenedAt,
  }) {
    return Score(
      id: id,
      title: title ?? this.title,
      composer: composer ?? this.composer,
      instrument: instrument ?? this.instrument,
      musicalKey: musicalKey ?? this.musicalKey,
      tags: tags ?? this.tags,
      favorite: favorite ?? this.favorite,
      fileName: fileName,
      originalName: originalName,
      pageCount: pageCount ?? this.pageCount,
      lastPage: lastPage ?? this.lastPage,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'composer': composer,
    'instrument': instrument,
    'musical_key': musicalKey,
    'tags': jsonEncode(tags),
    'favorite': favorite ? 1 : 0,
    'file_name': fileName,
    'original_name': originalName,
    'page_count': pageCount,
    'last_page': lastPage,
    'added_at': addedAt.millisecondsSinceEpoch,
    'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
  };

  factory Score.fromRow(Map<String, Object?> row) {
    final lastOpened = row['last_opened_at'] as int?;
    return Score(
      id: row['id'] as String,
      title: row['title'] as String,
      composer: row['composer'] as String? ?? '',
      instrument: row['instrument'] as String? ?? '',
      musicalKey: row['musical_key'] as String? ?? '',
      tags: (jsonDecode(row['tags'] as String? ?? '[]') as List).cast<String>(),
      favorite: (row['favorite'] as int? ?? 0) == 1,
      fileName: row['file_name'] as String,
      originalName: row['original_name'] as String?,
      pageCount: row['page_count'] as int? ?? 0,
      lastPage: row['last_page'] as int? ?? 1,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      lastOpenedAt: lastOpened == null ? null : DateTime.fromMillisecondsSinceEpoch(lastOpened),
    );
  }

  /// Texto usado na busca (sem acentos, minúsculo).
  String get searchText =>
      normalizeForSearch([title, composer, instrument, musicalKey, ...tags, originalName ?? ''].join(' '));
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

String normalizeForSearch(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}
