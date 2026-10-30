import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Ícones do app num lugar só. Material Symbols arredondados, com traço
/// fino (peso 300, definido no IconTheme) — mais leve que os Icons clássicos.
/// Para trocar o estilo inteiro, basta mudar aqui (ex.: `_sharp`).
abstract final class AppIcons {
  // Biblioteca
  static const IconData search = Symbols.search_rounded;
  static const IconData clear = Symbols.close_rounded;
  static const IconData sort = Symbols.sort_rounded;
  static const IconData add = Symbols.add_rounded;
  static const IconData library = Symbols.library_music_rounded;
  static const IconData favorite = Symbols.bookmark_rounded;
  static const IconData more = Symbols.more_horiz_rounded;
  static const IconData open = Symbols.menu_book_rounded;
  static const IconData editInfo = Symbols.edit_note_rounded;
  static const IconData delete = Symbols.delete_rounded;
  static const IconData tag = Symbols.sell_rounded;

  // Leitor
  static const IconData previous = Symbols.chevron_left_rounded;
  static const IconData next = Symbols.chevron_right_rounded;
  static const IconData singlePage = Symbols.article_rounded;
  static const IconData twoPages = Symbols.menu_book_rounded;
  static const IconData annotate = Symbols.stylus_note_rounded;
  static const IconData pen = Symbols.edit_rounded;
  static const IconData highlighter = Symbols.ink_highlighter_rounded;
  static const IconData text = Symbols.text_fields_rounded;
  static const IconData eraser = Symbols.ink_eraser_rounded;
  static const IconData strokeWidth = Symbols.line_weight_rounded;
  static const IconData undo = Symbols.undo_rounded;
  static const IconData redo = Symbols.redo_rounded;
  static const IconData clearPage = Symbols.layers_clear_rounded;
}
