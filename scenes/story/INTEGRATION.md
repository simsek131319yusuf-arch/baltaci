# Story entegrasyonu (orkestra için)

`Story` autoload'u hazır (`project.godot`'ta GameState'ten sonra). Oyun kodu sadece `Story.notify(event, ctx)` çağırır;
görülen sahneler `GameState.flags["story_<id>"]`'de, ödüller (altın/bayrak) sahne bitince ya da "Geç" ile verilir.
Diyalog kutusu ve toast, Story'nin çocuğu olan CanvasLayer'lar; hiçbir sahneye düğüm eklemek gerekmez.

Kural: **bloklayan diyalog sadece `camp_enter` ve `run_end`'de açılır.** Vardiya içi olaylar (`chain`, `depth`,
`tree_first_seen`) ~3 sn'lik küçük bir balon gösterir ve tam sahneyi sıraya koyar; sıra bir sonraki `run_end`
(sonuç paneli) ya da `camp_enter`'de oynar. Aynı olayı tekrar tekrar göndermek güvenlidir (tekrar kuyruğa girmez).

## 1. Kamp: `scenes/camp/camp.gd`, `_ready()`'nin en sonu
```gdscript
	if not args.has("autoshot"):   # ekran görüntüsü çalıştırmalarında diyalog açılmasın
		Story.notify.call_deferred("camp_enter", {"runs": GameState.runs, "gold": GameState.gold, "best_chain": GameState.best_chain, "max_depth": GameState.max_depth, "last_run": GameState.last_run})
```

## 2. Orman: `scenes/forest/forest.gd`

### zincir büyüdüğünde (`_begin_fall`, `_hud.show_chain_popup(n)` satırının yanında)
```gdscript
		if n >= 5: Story.notify("chain", {"n": n})
```

### yeni sütun derinliği (`ensure_forest` döngüsünün sonunda; kamera önündeki tamponu çıkar)
```gdscript
	var col := _next_col - int(Balance.forest.buffer_columns)
	if col > _story_col: _story_col = col; GameState.note_depth(col); Story.notify("depth", {"col": col})
```
Ek alan: `var _story_col: int = 0` (üst değişkenlere). `col_gte` karşılaştırması olduğu için her sütunda çağırmak sorun değil;
istenirse sadece `col % 5 == 0` iken çağır.

### bir ağaç türü ilk kez göründüğünde (`add_tree(id, ...)` içinde, ağaç oluşturulduktan sonra)
```gdscript
	if not _story_trees.has(id): _story_trees[id] = true; Story.notify("tree_first_seen", {"tree": id})
```
Ek alan: `var _story_trees: Dictionary = {}`. (Kalıcı "ilk kez" kontrolü Story'de; bu sözlük sadece oturumda spam'i keser.)
Tampon 14 sütun ilerde üretildiğinden tam "ekrana girdiği an" değil, biraz erken; sadece balon çıktığı için sorun değil.

### vardiya bitince (`apply_run_result` sonrası, `_hud.show_results(result)` ile aynı yerde)
```gdscript
	Story.notify("run_end", {"last_run": result, "depth": GameState.max_depth})
```
Sonuç panelinin sayılarının akışı bitmeden diyalog açılmasın istenirse önüne
`await get_tree().create_timer(2.5).timeout` koy (ya da `Story.notify.call_deferred` yerine bir `Timer`).

## 3. Test / önizleme çalıştırmaları
Testlerde `Story.ui_enabled = false` yap (diyalog UI'ı kurulmaz, sahneler anında biter). `--autoshot` yollarında
`notify` çağırma (1. maddedeki koruma).

## 4. Bağlam anahtarları (koşullar bunlara bakar)
| Koşul | Okuduğu değer |
|---|---|
| `runs_gte`, `gold_gte`, `best_chain_gte`, `max_depth_gte` | ctx'te varsa ctx, yoksa `GameState` |
| `chain_gte` | ctx `n`, yoksa ctx `chain`, yoksa `last_run.longest_chain` |
| `col_gte` | ctx `col` (ya da `depth`) |
| `tree` | ctx `tree` (tam eşitlik) |
| `flag` / `flag_not` | `GameState.flags[<ad>]` |
`_lte` ve `_eq` de desteklenir. Bilinmeyen koşul asla eşleşmez (sahne sessizce tetiklenmez).

## 5. Diğer API
`Story.is_playing()`, `Story.reset_story()` (ayarlardaki "hikayeyi sıfırla" için; ödenen altın geri alınmaz),
sinyaller `beat_started(id)` / `beat_finished(id)`. Önizleme: `~/bin/godot --path . res://scenes/story/story_demo.tscn`
(`-- --autoshot=out.png` ile `out_letter/mid/after/emote/toast.png`; `-- --beat=<id>` ile başka sahne).
Hikaye metni/tetikleyiciler: `data/story.json`. Yeni görsel kimlikleri: `story/hoca`, `story/kemal`, `story/letter`,
`story/pawprint` (karakter `portrait` alanı); eksik görselde baş harfli renkli daire çizilir.
