// FamilySearch: ПОШУК У КАТАЛОЗІ за місцем (шифри фондів/справ, номери DGS) під вашим власним акаунтом.
// Не завантажує зображення масово (умови використання FamilySearch цього не дозволяють без письмового дозволу).
// FS_STORAGE_STATE — шлях до файлу storageState, збереженого ПІСЛЯ ручного входу; тримайте його поза репозиторієм.
// node browser/fs_catalog.js "<місце>" "<підрядок-теми-для-кліку>"
const { chromium } = require('playwright');
const [,, place, subject] = process.argv;
const state = process.env.FS_STORAGE_STATE;
if (!state) { console.error('Задайте FS_STORAGE_STATE'); process.exit(1); }
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ storageState: state, viewport: { width: 1300, height: 1600 } });
  const p = await ctx.newPage();
  await p.goto('https://www.familysearch.org/en/search/catalog/results?q.place=' + encodeURIComponent(place), { timeout: 60000, waitUntil: 'domcontentloaded' });
  await p.waitForTimeout(9000);
  await p.keyboard.press('Escape').catch(() => {});
  if (subject) await p.getByText(subject, { exact: false }).first().click({ timeout: 8000 }).catch(e => console.log('subject click err', e.message.slice(0, 80)));
  await p.waitForTimeout(6000);
  const rows = await p.evaluate(() => [...document.querySelectorAll('a')].map(a => ({ t: (a.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 120), h: a.getAttribute('href') })).filter(x => x.h && /catalog\/(koha|olib)/.test(x.h)));
  const seen = new Set();
  rows.forEach(r => { if (!seen.has(r.h)) { seen.add(r.h); console.log(' ', r.h, '|', r.t); } });
  await b.close();
})();
