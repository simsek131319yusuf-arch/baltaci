// Kullanım: node gemget.cjs <sohbet-yolu> <cikti.png>
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const fs = require("fs"), path = require("path");
(async () => { const [yol, out] = process.argv.slice(2);
const b = await chromium.connectOverCDP("http://127.0.0.1:9333");
const p = await b.contexts()[0].newPage(); await p.goto("https://gemini.google.com/app/" + yol, { waitUntil: "load" }); await p.waitForTimeout(6000);
const img = p.locator("model-response img").first();
await img.hover(); await p.waitForTimeout(800);
const labels = await p.$$eval("model-response button", bs => bs.map(x => x.getAttribute("aria-label")).filter(Boolean));
console.log("butonlar:", [...new Set(labels)].join(" | "));
try {
  const dl = p.waitForEvent("download", { timeout: 30000 });
  await p.locator('model-response button[aria-label*="ndir"], model-response button[aria-label*="ownload"]').first().click({ timeout: 5000 });
  const d = await dl; await d.saveAs(out); console.log("TAM", out);
} catch (e) {
  const b64 = await img.evaluate((im) => { const c = document.createElement("canvas"); c.width = im.naturalWidth; c.height = im.naturalHeight; c.getContext("2d").drawImage(im, 0, 0); return c.toDataURL("image/png").split(",")[1]; });
  fs.writeFileSync(out, Buffer.from(b64, "base64")); console.log("ONIZLEME", out, e.message.slice(0, 80));
}
await p.close(); process.exit(0); })();
