# Baltacı — ajan sözleşmesi

Godot 4.7.2, GDScript, 2D, GL Compatibility. Viewport 1600×900, stretch `canvas_items`, aspect `keep` (letterbox).
Godot yolu (Git Bash): `~/bin/godot` (konsol exe). Headless test: `~/bin/godot --headless --path . -s tests/<x>.gd`.
Tasarım özeti: `docs/GELISTIRME-NOTLARI.md` (tam GDD geliştiricinin özel notlarında). Bu sürüm = **1. hafta dikey dilimi**.

## Kurallar
- Sadece **kendi sahip olduğun dosyalara** yaz. Ortak dosyalar (aşağıda "orkestra") değişecekse değiştirme, raporunda iste.
- `git` komutu çalıştırma (commit/add/checkout yok).
- String anahtar/dosya adı üretirken `to_lower()` kullanma (Türkçe I hatası). Sabit ASCII anahtar kullan.
- Oyun içi metinler Türkçe. Kod tanımlayıcıları İngilizce.
- Sayıları koda gömme: `Balance` (data/*.json) üzerinden oku. Yeni ayar gerekiyorsa önce kendi sahnende `@export` sabiti yap ve raporda JSON'a taşınmasını öner.
- Görseller her an eksik olabilir: `Art.tex("trees/kavak_0")` null dönerse placeholder çiz (renkler trees.json'da). Asla eksik görselde çökme.

## Dosya sahipliği
| Sahip | Dosyalar |
|---|---|
| orkestra (Zela) | `project.godot`, `data/*.json`, `scripts/autoload/*`, `CONTRACT.md` |
| ajan-orman | `scenes/forest/**`, `tests/test_forest*.gd` |
| ajan-kamp | `scenes/camp/**`, `scenes/ui/**`, `tests/test_economy*.gd`, `tests/run_all.gd` |
| ajan-görsel | `art/**` |

## Autoload API (hazır, değiştirme)
- `Balance` — `trees{id:{name,hp,height,width,log_value,logs,xp,color_trunk,color_crown}}`, `tree_order`, `forest{buffer_columns,spacing_min,spacing_max,ground_y}`, `chain_bonus_max`, `base_stats`, `upgrades[]`, `pick_tree(col, rng) -> id`, `compute_stat(stat, levels)`, `upgrade_cost(id, level)`, `is_maxed(id, level)`, `run_payout(logs, longest_chain) -> {sales, chain_bonus, total}`.
- `GameState` — `gold`, `levels`, `best_chain`, `runs`, `last_run`, signal `changed`, `stat(name)`, `level_of(id)`, `next_cost(id)`, `can_buy(id)`, `buy(id)`, `apply_run_result(logs, longest_chain, trees_felled, duration) -> Dictionary`, `save_game()` (tmp+doğrula+.bak+rename), `load_game()` (bozuk dosya → save.corrupt.json, .tmp/.bak yedeği), `save_path` (testler `user://test_*.json` kullanır), `persist` (false = hiç yazma), `reset()`, `to_dict()`, `from_dict(d)`.
- `Art` — `tex(id) -> Texture2D|null`, `has(id)`.

Statlar (`GameState.stat`): `axe_damage`, `swing_interval` (sn), `crit_chance` (0..1), `crit_multiplier`, `run_time` (sn), `fall_power`, `chain_bonus_per_link`.

## Sahneler ve geçiş
- `res://scenes/camp/camp.tscn` — ana sahne (ajan-kamp). "Vardiyaya Başla" → `get_tree().change_scene_to_file("res://scenes/forest/forest.tscn")`.
- `res://scenes/forest/forest.tscn` — vardiya (ajan-orman). Tur bitince `GameState.apply_run_result(...)` çağırır, kendi sonuç panelini `last_run` ile gösterir, "Kampa Dön" → camp.tscn.

## Run result (`GameState.last_run`)
`{logs:{tree_id:int}, longest_chain:int, trees_felled:int, duration:float, sales:float, chain_bonus:float, total:float, gold_after:float}`

## Oynanış kuralları (dikey dilim)
- Orman yandan görünüş ve **sonsuz**: kamera önünde `forest.buffer_columns` sütun üretilir, çok gerideki ağaçlar silinir. Ağaçlar aralarında `spacing_min..max` px, kökler `ground_y`'de. Sütun indeksi büyüdükçe (sağa) `Balance.pick_tree` daha değerli türler verir. Kamera yatay kayar (fare ekran kenarına yaklaşınca + oyuncu sağa ilerledikçe).
- Balta imleci fareyi takip eder, `swing_interval` aralıkla **otomatik** sallanır. İmlecin altındaki ayakta duran ağaca `axe_damage` vurur (`crit_chance` ile ×`crit_multiplier`). İmleç ağaç gövdesinin x aralığında (±genişlik/2 + tolerans) ve kök ile tepe arasında olmalı.
- **Devrilme:** can ≤ 0 → ağaç, imlecin gövdeye göre hangi taraftan vurduğunun **tersine** devrilir (soldan vurulan sağa düşer). Kökü pivot alıp ~0.6 sn'de yere iner (ivmelenerek). Yere değdiğinde düşme yönünde kök x'i `(x, x + yön·height]` aralığındaki ayakta ağaçlara `height × fall_power` hasar verir. Onlar ölürse **aynı yöne** devrilir → zincir. Zincir uzunluğu = aynı ilk devrilmeden doğan toplam devrilen ağaç. "Zincir x3!" uçan yazısı. Turun en uzun zinciri `longest_chain`.
- Devrilen ağaç yere değince `logs` (trees.json) kadar tomruk sayar, sonra solar; yerinde kütük kalır.
- Süre `run_time`. Bitiş: süre dolar ya da "Paydos" butonu. Bitişte yarım kalan balta darbesi tamamlanır, balta durur, havadaki ağaçların hepsi yere değene kadar (en fazla 6 sn) beklenir, sonra `apply_run_result`. Zincir uzunluğu ve tomruklar aynı olaydan (gövdenin yere değmesi) sayılır. Toplam zincir bonusu `chain_bonus_max` ile sınırlı.
- Sonuç paneli: tür başına tomruk × değer, zincir bonusu, toplam, yeni bakiye. Sayılar `last_run`'dan; ayrı hesaplama yok.

## Görsel kimlikleri (`art/sprites/<id>.png`, RGBA, gerçek alfa)
- `trees/<id>_0..3` (0 sağlam → 3 en hasarlı), `trees/<id>_stump`; kök noktası görselin alt-orta pikseli. Tür id'leri: `kavak`, `cam`, `ladin`.
- `cat/idle`, `cat/swing` — maskot **Pipsy** (oduncu yavru köpek; referans `art/raw/pipsy_ref.png`). Kimlik adı geriye uyum için `cat/` kaldı.
- `axe` — imleç baltası; sap ucu = döndürme pivotu, görselin alt-orta pikseli.
- `bg/sky`, `bg/far`, `bg/mid`, `bg/ground` — paralaks katmanları (1600 px genişlikte yatay tekrar edebilir).
- `fx/chip`, `fx/leaf`, `fx/log` — parçacık.
- `ui/coin`, `ui/log`, `ui/clock`, `ui/chain`, `ui/panel` — arayüz.
Boyut ve pivotlar `art/manifest.json`'da (ajan-görsel yazar). Kod, görsel varsa boyutunu trees.json `height`/`width`'e ölçekler.

## Doğrulama
- Her ajan headless test yazar ve çalıştırır. Ayrıca `~/bin/godot --path . -- --autoshot=<png>` gibi otomatik ekran görüntüsü yolunu kendi sahnesinde destekler (komut satırı argümanı `OS.get_cmdline_user_args()`), ki sonuç gözle kontrol edilebilsin.
