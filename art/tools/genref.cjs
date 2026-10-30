// node genref.cjs <ref.png> "<prompt>"  -> prints CHAT <id>
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const [ref, prompt] = process.argv.slice(2);
(async () => {
  const b = await chromium.connectOverCDP("http://127.0.0.1:9333");
  const p = await b.contexts()[0].newPage();
  try {
    await p.goto("https://gemini.google.com/app", { waitUntil: "load" });
    await p.waitForTimeout(4000); await p.keyboard.press("Escape"); await p.waitForTimeout(500);
    await p.locator('button[aria-label="Yükleme ve araçlar"]').click(); await p.waitForTimeout(1000);
    const fc = p.waitForEvent("filechooser", { timeout: 15000 });
    await p.locator('.cdk-overlay-container button[aria-label^="Dosya yükleyin"]').click();
    const kabul = p.locator('.cdk-overlay-container button:has-text("Kabul")');
    if (await kabul.isVisible({ timeout: 2500 }).catch(() => false)) { await kabul.click(); console.log("kabul tiklandi"); }
    await (await fc).setFiles(ref); console.log("dosya secildi");
    await p.waitForTimeout(6000);
    const box = p.locator('div[contenteditable="true"]').first();
    await box.click(); await box.fill(prompt); await p.waitForTimeout(500); await p.keyboard.press("Enter");
    const t0 = Date.now(); let ok = false;
    while (Date.now() - t0 < 180000) {
      await p.waitForTimeout(3000);
      const im = p.locator("model-response img");
      if (await im.count() && (await im.first().evaluate(e => e.naturalWidth).catch(() => 0)) > 200) { ok = true; break; }
    }
    if (ok) console.log("CHAT " + p.url().split("/app/")[1]);
    else { console.log("GORSEL YOK: " + (await p.locator("model-response").last().innerText().catch(() => "")).slice(0, 300)); await p.screenshot({ path: "genref-hata.png" }); }
  } catch (e) { console.log("HATA " + e.message.slice(0, 300)); await p.screenshot({ path: "genref-hata.png" }).catch(()=>{}); }
  await p.close(); process.exit(0);
})();
