const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const prompt = process.argv[2];
(async () => {
  const b = await chromium.connectOverCDP("http://127.0.0.1:9333");
  const p = await b.contexts()[0].newPage();
  await p.goto("https://gemini.google.com/app", { waitUntil: "load" });
  await p.waitForTimeout(4000); await p.keyboard.press("Escape");
  const box = p.locator('div[contenteditable="true"]').first();
  await box.click(); await box.fill(prompt); await p.keyboard.press("Enter");
  const t0 = Date.now(); let ok = false;
  while (Date.now() - t0 < 180000) {
    await p.waitForTimeout(3000);
    const im = p.locator("model-response img");
    if (await im.count() && (await im.first().evaluate(e => e.naturalWidth).catch(() => 0)) > 200) { ok = true; break; }
  }
  console.log(ok ? "CHAT " + p.url().split("/app/")[1] : "GORSEL YOK: " + (await p.locator("model-response").last().innerText().catch(() => "")).slice(0, 300));
  await p.close(); process.exit(0);
})();
