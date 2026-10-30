# Geliştirme notları: Baltacı nasıl yapıldı

Tarih: 30 Ekim 2026. İlk oynanabilir sürüme kadar her şey tek gecede yapıldı. Yusuf yönetti; Claude Code (Zela) kodu yazan ajanları orkestre etti.

Bu belge hangi aşamada ne kullanıldığını, neden seçildiğini ve nerede takılındığını anlatır.

---

## Aşama 0: Türü anlamak (tersine mühendislik)

**Amaç:** "süreli tur + kalıcı ilerleme" türündeki bir oyunun (Steam'deki *Astro Kitty Space Mining*, Unity) mekaniğini ve ekonomisini anlamak. **Kodu, görselleri ve sayıları alınmadı.** Sadece türün nasıl kurulduğu incelendi; Baltacı'nın mekanikleri sıfırdan tasarlandı.

| Araç | Ne için |
|---|---|
| **REA** (reverse-engineering MCP sunucusu) | `Assembly-CSharp.dll` kimliği, tip listesi, metot sayıları, kod içindeki string'ler |
| **.NET 8 SDK + ilspycmd 9.1** | Mono C# derlemesini okunur kaynağa çevirmek. ilspycmd'nin son sürümü daha yeni SDK istedi, 9.1'e inildi. |
| **UnityPy + TypeTreeGeneratorAPI** | ScriptableObject'lerdeki denge sayılarını okumak |
| Python | Veriyi özetlemek |

**Çıkan dersler** (Baltacı'ya tasarım kuralı olarak geçti):
- Kayıt dosyası adını `ToLower()` ile üretmek Türkçe Windows'ta `skıll_save.json` yapıyor; dil değişince kayıt "kayboluyor". Bu yüzden Baltacı'da sabit ASCII anahtar kullanılıyor.
- "Multiplier" adlı statlar aslında düz toplama yapıyordu. Baltacı'da ismi neyse davranışı o.
- Ekranda gösterilen ve yatırılan para farklı yoldan hesaplanıyordu. Baltacı'da ikisi tek kaynaktan geliyor (`Balance.run_payout`).
- Kayıtta sürüm alanı yoktu. Baltacı'da `save_version` ve migration var.

**UnityPy tuzağı:** typetree üreteci açıkken tüm MonoBehaviour'ları okumak SerializeReference yüzünden çöküyor. Çözüm iki geçişli okuma: önce script adlarını topla, sonra sadece gerekenleri oku.

## Aşama 1: Tasarım

- Tür: yandan görünüşlü ağaç kesme incremental.
- **İmza mekanik:** devrilme zinciri. Ağaç vurulduğu tarafın tersine devriliyor, boyu kadar ötedeki ağaçlara hasar veriyor, zincir domino gibi ilerliyor. Combo zincirin uzunluğu.
- Ekonomi: tomruk → altın; ileride hızar, sipariş tahtası ve fidanlık.
- Kararlar: sadece Steam/masaüstü (web sürümü yok), görseller yapay zekâ ile, ekip Yusuf + Zela.
- Maskot önce oduncu kedi olarak düşünüldü, sonra **Pipsy**'ye (arkadaşın sarı köpek karakteri, izinli) geçildi.

## Aşama 2: Motor seçimi

| Aday | Sonuç |
|---|---|
| TypeScript + PixiJS + Electron | En hızlı yol olarak önerildi |
| Rust (Bevy) | Reddedildi. UI ağırlıklı bir oyunda arayüzü zayıf, derleme döngüsü yavaş; performansa ihtiyaç yok. |
| Unity | Güçlü, ama editör merkezli; ajanların düz metinle yönetmesi zor |
| **Godot 4.7.2 (GDScript)** | **Seçildi.** Sahneler düz metin (`.tscn`), headless test kolay, 2D ve UI sağlam, Steam desteği GodotSteam ile. |

Kurulum `winget install GodotEngine.GodotEngine` ile yapıldı. Konsol exe'si `~/bin/godot` sarmalayıcısıyla çağrılıyor.

## Aşama 3: Ajan orkestrasyonu

Orkestratör (Claude Opus) iskeleti kendisi kurdu. Ajanların paralel çalışırken birbirinin dosyasını ezmemesi için önce **sözleşme** yazıldı:
- `CONTRACT.md`: dosya sahipliği tablosu, autoload API'si, oyun kuralları, görsel kimlikleri.
- Ortak çekirdek: `Balance`, `Art`, `GameState` ve `data/*.json`.
- Önceden elle hesaplanmış beklenen değerlerle smoke testi.

Ardından iş alt ajanlara (Claude Sonnet) dağıtıldı. Her ajanın sahip olduğu dosyalar ayrıydı ve git kullanmaları yasaktı.

| Ajan | İş |
|---|---|
| orman | Vardiya sahnesi: ağaçlar, balta, devrilme zinciri, HUD, sonuç paneli, testler |
| kamp | Hub, balta tezgahı, tema, sayı biçimlendirme, test koşucusu |
| **denetçi** | Kodu yazmamış, bağımsız bir ajan. Görevi "çalışıyor mu doğrula" değil, "nasıl bozulur, bul" idi. 9 bulgu çıkardı. |
| düzeltme | Bulguları kapattı: vardiya sonunda kaybolan tomruklar, kayıt bozulması, sabit ormanda sıkışan ekonomi (sonsuz ormana geçildi), ekran oranı |
| görsel (3 tur) | Nano Banana ile 38 sprite |
| animasyon | Juice: hit-stop, yay salınımı, yer çekimiyle devrilme, parçacıklar, ekran sarsıntısı, geçişler |
| hikaye | Veriye dayalı diyalog sistemi, 8 sahnelik "Dedenin Kampı" |
| entegrasyon | Hikaye bağlantıları; bulut oturumuna devredilmeden önce yarıda durduruldu |

**Kurallar:**
- Her ajan headless test ve `--autoshot` ekran görüntüsüyle kendi işine baktı. Orkestratör her sonucu testleri yeniden çalıştırıp ekran görüntülerine kendisi bakarak doğruladı.
- Gerçek kayıt dosyasının md5'i her turdan önce ve sonra karşılaştırıldı. Testler `GameState.save_path` ve `persist` ile ayrı dosyaya yazıyor.
- Denge `tools/sim_balance.gd` ile ölçüldü: mükemmel nişan alan bir botla vardiya başına ortalama altın hesaplandı. Hedef "her şey ~30 vardiyada maksimum" idi.

## Aşama 4: Görseller (Nano Banana)

**Yol:** Gemini web arayüzü, kullanıcının giriş yapmış Brave profili ve Playwright `connectOverCDP` (port 9333). Script'ler `art/tools/` altında:
- `genref.cjs`: referans görsel yükleyerek üretir.
- `pipsy.cjs`: referanssız üretir.
- `gemget.cjs`: üretilen görselin tam boyunu indirir.

**Tuzaklar ve çözümleri:**
1. **Gemini arayüzü değişti.** İlk görsel ajanının "kapat düğmesi" araması (`aria-label*="apat"`) yeni arayüzdeki "Aç/Kapat: Tümü" düğmesine tıklıyor, istem hiç gönderilmiyordu. Çözüm: sadece Escape'e basmak.
2. **Gemini zemin rengine birebir uymuyor.** "#FF00FF magenta" isteyince #B83C78 geldi. Arka plan temizleyici renk varsaymıyor, görselin kenarından örnekliyor.
3. **"Transparent" istenmiyor.** Üretici sahte damalı desen boyuyor. Bunun yerine düz renkli zemin istenip Python/PIL ile maskeleniyor; ardından PNG renk tipi kontrol ediliyor (6 = gerçek alfa) ve görsel koyu ve açık zeminde gözle kontrol ediliyor.
4. **Referans sızıntısı.** Pipsy görseli referans verildiğinde ağaç görsellerine hayalet köpek karıştı. Karakter olmayan görseller referanssız, stil tarifiyle üretildi.
5. **Hasar aşamaları yeniden üretilmiyor.** Her ağacın `_1.._3` aşamaları `_0`'dan prosedürel olarak türetildi (gövdede çentik ve çatlak), böylece ağaç her aşamada aynı kalıyor.
6. Pipsy önce tarifle "benzeri" olarak üretildi. Arkadaşın izniyle emoji ekran görüntüsü kesilip büyütüldü ve referans olarak yüklendi; birebir karakter elde edildi.

Toplam üretim: yaklaşık 26 başarılı üretim, birkaç ağ hatası ve 3 hayalet köpekli deneme. Kullanılan istemler `art/prompts/promptlar.md` içinde.

## Aşama 5: Test ve doğrulama

- `tests/run_all.gd`: her test ayrı süreçte, 60 sn zaman aşımıyla çalışıyor. Şu an 6/6 geçiyor: smoke, ekonomi, sayı biçimi, orman, juice, hikaye.
- `--autoshot`, `--autoshot-seq`: ekran görüntüsü ve kare dizisi. Animasyonun akıcılığı kare kare bakılarak kontrol edildi.
- Bilinen sınır: oyun henüz bir insan tarafından uzun süre elle oynanmadı. His ayarları sonraki iş.

## Aşama 6: Repo ve bulut

- GitHub reposu, `.gitignore` (`.godot/` ve ham üretimler hariç), MIT lisansı (yalnızca kod; görseller ve Pipsy hariç).
- Kalan işler `HANDOFF.md` ile bulut oturumuna (claude.ai/code) devredildi.
- Nano Banana yalnız geliştiricinin bilgisayarında çalışıyor; bulutta yeni görsel üretilemiyor.

## Kısa ders listesi
- Paralel ajanlarda önce sözleşme ve dosya sahipliği belirlenmeli, sonra iş dağıtılmalı.
- Kodu yazan ajan kendi işini denetleyemez; ayrı bir denetçi gerekli.
- Bir ajan "çalışıyor" dediğinde orkestratör testleri kendisi çalıştırmalı ve görüntüyü kendisi açmalı.
- Ekonomi elle değil simülatörle ayarlanmalı. Sabit 60 ağaçlık orman, simülasyon ortaya çıkarana kadar fark edilmemişti.
- Yapay zekâ görsellerinde tutarlılık için tek referans görsel ve yeniden üretmek yerine türetme.
