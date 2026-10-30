# Estante

App desktop (Flutter/Windows) para organizar, abrir e anotar partituras em PDF.

## Rodar

```
flutter pub get
flutter run -d windows
```

## Estrutura

```
lib/
  main.dart                          inicialização (pdfrx, pastas, banco)
  data/
    app_storage.dart                 pastas do app (%APPDATA%\...\Partituras)
    score.dart                       modelo da partitura + busca sem acento
    score_repository.dart            SQLite (package:sqlite3), importação, exclusão
  annotations/
    annotation_models.dart           traço, marca-texto, texto (coords normalizadas 0..1)
    annotation_controller.dart       ferramentas, desfazer/refazer, autosave em JSON
    annotation_layer.dart            camada de desenho por cima da página + painter
  screens/
    library_controller.dart          estado da biblioteca: busca, filtros, ordenação (signals)
    library_screen.dart              biblioteca: grade, busca, tags, favoritas, ordenação
    score_details_dialog.dart        editar título, compositor, instrumento, tom, tags
    viewer_controller.dart           estado do leitor: PDF, página, 1/2 páginas, zoom
    viewer_screen.dart               leitor 1 ou 2 páginas, zoom, atalhos, barra de anotação
```

## Estado (signals)

O estado é feito com [`signals_flutter`](https://pub.dev/packages/signals_flutter), sem `ChangeNotifier` nem `setState`:

- Controllers (`*_controller.dart`, `ScoreRepository`) expõem `signal`/`computed`.
- Widgets estendem `SignalWidget` (ou `SignalStatefulWidget` quando precisam ser donos de
  algo descartável) e se reconstroem sozinhos quando um `.value` lido no build muda.
- Só é rastreado o que é lido **direto no build**. Builders que rodam depois (`LayoutBuilder`,
  `itemBuilder` de listas) não contam: leia antes ou use um `SignalBuilder`.
- Signals usam `==`: listas e mapas são trocados por novos, nunca mutados no lugar
  (exceção: o traço ativo, que usa `set(..., force: true)`).
- Coisas que redesenham a cada frame (traço da caneta) usam o signal como `repaint` do
  `CustomPainter`, sem rebuild.

Os PDFs importados são copiados para a pasta do app; o original nunca é alterado.
As anotações ficam em `annotations/<id>.json`.

## Atalhos

| Onde | Tecla | Ação |
|---|---|---|
| Biblioteca | Ctrl+O | Importar PDF |
| Biblioteca | Ctrl+F | Buscar |
| Leitor | → ↓ PageDown Espaço | Próxima página (pedais de virar página) |
| Leitor | ← ↑ PageUp | Página anterior |
| Leitor | Home / End | Primeira / última |
| Leitor | D | Alterna 1 ou 2 páginas |
| Leitor | 0 | Reseta o zoom |
| Leitor | P / H / T / E | Caneta / marca-texto / texto / borracha |
| Leitor | Botão direito | Borracha rápida |
| Leitor | Ctrl+Z / Ctrl+Y | Desfazer / refazer |
| Leitor | Esc | Sai da edição / volta à biblioteca |

No modo leitura, clicar no terço esquerdo ou direito da tela vira a página.
