import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

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

/// Continua stateful só porque é dono dos TextEditingControllers, que
/// precisam ser descartados quando o diálogo sai da tela (depois da
/// animação de saída). O resto do estado é signal.
class _ScoreDetailsDialog extends SignalStatefulWidget {
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
  late final _tags = signal<List<String>>(widget.score.tags);
  late final _favorite = signal(widget.score.favorite);

  @override
  void dispose() {
    for (final c in [_title, _composer, _instrument, _key, _tagInput]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTag(String raw) {
    final tags = [..._tags.value];
    for (final part in raw.split(',')) {
      final tag = part.trim();
      if (tag.isNotEmpty && !tags.any((t) => normalizeForSearch(t) == normalizeForSearch(tag))) {
        tags.add(tag);
      }
    }
    _tags.value = tags;
    _tagInput.clear();
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
        tags: _tags.value,
        favorite: _favorite.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = _tags.value;
    final suggestions = widget.knownTags.where((t) => !tags.contains(t)).toList();
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
                      for (final tag in tags)
                        InputChip(label: Text(tag), onDeleted: () => _tags.value = [...tags]..remove(tag)),
                      for (final tag in suggestions.take(12))
                        ActionChip(
                          avatar: const Icon(AppIcons.add, size: 16),
                          label: Text(tag),
                          onPressed: () => _tags.value = [...tags, tag],
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Favorita'),
                  value: _favorite.value,
                  onChanged: (v) => _favorite.value = v,
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
