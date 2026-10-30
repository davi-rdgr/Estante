import 'package:flutter/material.dart';

import '../data/score.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Edita título, compositor, instrumento, tom, tags e favorita.
/// Retorna a partitura alterada, ou `null` se cancelar.
Future<Score?> showScoreDetailsDialog(BuildContext context, Score score, {List<String> knownTags = const []}) {
  return showDialog<Score>(
    context: context,
    builder: (context) => _ScoreDetailsDialog(score: score, knownTags: knownTags),
  );
}

class _ScoreDetailsDialog extends StatefulWidget {
  const _ScoreDetailsDialog({required this.score, required this.knownTags});

  final Score score;
  final List<String> knownTags;

  @override
  State<_ScoreDetailsDialog> createState() => _ScoreDetailsDialogState();
}

class _ScoreDetailsDialogState extends State<_ScoreDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.score.title);
  late final _composer = TextEditingController(text: widget.score.composer);
  late final _instrument = TextEditingController(text: widget.score.instrument);
  late final _key = TextEditingController(text: widget.score.musicalKey);
  final _tagInput = TextEditingController();
  late final List<String> _tags = [...widget.score.tags];
  late bool _favorite = widget.score.favorite;

  @override
  void dispose() {
    for (final c in [_title, _composer, _instrument, _key, _tagInput]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTag(String raw) {
    for (final part in raw.split(',')) {
      final tag = part.trim();
      if (tag.isNotEmpty && !_tags.any((t) => normalizeForSearch(t) == normalizeForSearch(tag))) {
        _tags.add(tag);
      }
    }
    _tagInput.clear();
    setState(() {});
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_tagInput.text.trim().isNotEmpty) _addTag(_tagInput.text);
    Navigator.pop(
      context,
      widget.score.copyWith(
        title: _title.text.trim(),
        composer: _composer.text.trim(),
        instrument: _instrument.text.trim(),
        musicalKey: _key.text.trim(),
        tags: _tags,
        favorite: _favorite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.knownTags.where((t) => !_tags.contains(t)).toList();
    return AlertDialog(
      title: const Text('Informações da partitura'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.lg,
              children: [
                TextFormField(
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Título'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um título' : null,
                ),
                TextFormField(
                  controller: _composer,
                  decoration: const InputDecoration(labelText: 'Compositor'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _instrument,
                        decoration: const InputDecoration(labelText: 'Instrumento'),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: _key,
                        decoration: const InputDecoration(labelText: 'Tom', hintText: 'ex.: Ré m'),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _tagInput,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'Digite e tecle Enter (ex.: recital, estudo)',
                  ),
                  onSubmitted: _addTag,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in _tags)
                        InputChip(label: Text(tag), onDeleted: () => setState(() => _tags.remove(tag))),
                      for (final tag in suggestions.take(12))
                        ActionChip(
                          avatar: const Icon(AppIcons.add, size: 16),
                          label: Text(tag),
                          onPressed: () => setState(() => _tags.add(tag)),
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Favorita'),
                  value: _favorite,
                  onChanged: (v) => setState(() => _favorite = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
