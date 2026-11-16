// Temu: пошук спорядження для зимового походу (Чорногора, 22.12.2026) по 11 категоріях.
//
// ЗАПУСКАТИ ЛОКАЛЬНО (ваш ПК/Mac), НЕ в хмарній Claude-сесії — там temu.com технічно
// недосяжний для живого рендеру (DNS-блок на WebFetch + класифікатор безпеки забороняє
// headless-браузер проти шопінг-сайтів у sandbox). Тут це просто ваш звичайний браузер
// з вашої IP — Temu рендериться нормально.
//
// Чому евристика ("будь-який <a> з ціною в тексті"), а не жорсткі CSS-класи Temu:
// клас-неймінг у них хешований і змінюється від збірки до збірки, а я (Claude) не мав
// живого доступу подивитись поточний DOM — жорсткі селектори були б вгадуванням і
// зламались би за тиждень. Евристика грубіша, але чесна: що бачите в консолі — те й є.
//
// Якщо Temu покаже CAPTCHA/"verify you are human" — скрипт зупиняється і каже прямо,
// НЕ намагається обійти (та сама етика, що в kinship-toolkit/browser: перевірка і
// рішення — за людиною, а не за скриптом).
//
// Використання:
//   npm install playwright   (раз, якщо ще нема)
//   node gear-hunt/temu-search.js [output.json]
//
// Результат: консольний вивід + JSON-файл. Скиньте їх Claude — лише тоді можлива
// чесна жорстка оцінка "топ / не варто", бо тільки тоді є реальні URL/ціни/тексти.

const { chromium } = require('playwright');
const fs = require('fs');

const QUERIES = [
  { id: 'gaiters', label: 'Гамаші сніжні високі (гідростовп, не water-resistant)', q: 'waterproof snow gaiters tall velcro' },
  { id: 'socks', label: 'Мериносові трекінгові/лижні шкарпетки', q: 'merino wool ski hiking socks' },
  { id: 'axe_leash', label: 'Ліньярд льодоруба', q: 'ice axe leash tether' },
  { id: 'hand_warmer', label: 'Грілки-клік реюзабл (ацетат натрію)', q: 'reusable hand warmer click heat pad' },
  { id: 'heated_glove_liner', label: 'Батарейні рукавички-ліньори, сенсорні (Рейно!)', q: 'rechargeable heated glove liner touchscreen' },
  { id: 'mitts', label: 'Зовнішні рукавиці-мітенки альпіністські', q: 'winter mountaineering mitts gloves' },
  { id: 'dry_bag', label: 'Сет сухих мішків (запечатані шви, roll-top)', q: 'ultralight dry bag set waterproof' },
  { id: 'whistle', label: 'Свисток без кульки + стробоскоп-маячок', q: 'pealess whistle survival strobe light' },
  { id: 'phone_case', label: 'Термочохол для телефону (холод)', q: 'thermal insulated phone pouch case cold' },
  { id: 'headlamp', label: 'Налобний фонар холодостійкий + літієві батарейки', q: 'headlamp rechargeable waterproof winter' },
  { id: 'sleep_pad', label: 'Надувний килимок (R-value) + піняка під низ', q: 'ultralight inflatable sleeping pad high R value winter' },
];

const PRICE_RE = /[$€£]\s?\d{1,4}([.,]\d{1,2})?/;
const BLOCK_MARKERS = ['verify you are human', 'unusual traffic', 'captcha', 'are you a robot', 'access denied'];

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

(async () => {
  const browser = await chromium.launch({ headless: false }); // headed — менший шанс бот-детекту
  const page = await browser.newPage({ viewport: { width: 1400, height: 1700 } });
  const results = {};

  for (const { id, label, q } of QUERIES) {
    console.log(`\n### ${label} ("${q}")`);
    const url = 'https://www.temu.com/search_result.html?search_key=' + encodeURIComponent(q);
    try {
      await page.goto(url, { timeout: 45000, waitUntil: 'domcontentloaded' });
      await page.waitForTimeout(6000); // дати SPA відрендеритись

      const bodyTextLower = (await page.evaluate(() => document.body.innerText)).toLowerCase();
      if (BLOCK_MARKERS.some((m) => bodyTextLower.includes(m))) {
        console.log('  ЗАБЛОКОВАНО (CAPTCHA/bot-check) — пройдіть перевірку вручну в цьому ж вікні, скрипт не обходить це.');
        results[id] = { label, q, blocked: true, items: [] };
        await sleep(4000);
        continue;
      }

      const items = await page.evaluate((priceSrc) => {
        const priceRe = new RegExp(priceSrc);
        const anchors = [...document.querySelectorAll('a')];
        const out = [];
        for (const a of anchors) {
          const txt = (a.innerText || '').replace(/\s+/g, ' ').trim();
          const href = a.getAttribute('href');
          if (!href || !txt) continue;
          if (priceRe.test(txt)) out.push({ text: txt.slice(0, 160), href });
        }
        return out;
      }, PRICE_RE.source);

      const seen = new Set();
      const deduped = items
        .filter((it) => {
          if (seen.has(it.href)) return false;
          seen.add(it.href);
          return true;
        })
        .slice(0, 20);

      deduped.forEach((it) => console.log('  ', it.text, '|', it.href));
      if (!deduped.length) {
        console.log('  (нічого з ціною в тексті лінку не знайдено — можливо треба довше чекати рендер або скролити сторінку)');
      }

      results[id] = { label, q, blocked: false, items: deduped };
    } catch (e) {
      console.log('  ПОМИЛКА:', e.message.slice(0, 150));
      results[id] = { label, q, error: e.message.slice(0, 150), items: [] };
    }
    await sleep(3000); // пауза між запитами — та сама етика ввічливості, що в geneteka.js
  }

  const outPath = process.argv[2] || `temu-results-${new Date().toISOString().slice(0, 10)}.json`;
  fs.writeFileSync(outPath, JSON.stringify(results, null, 2), 'utf8');
  console.log('\nЗбережено:', outPath, '— скиньте цей файл Claude для жорсткого вердикту по реальних лотах.');

  await browser.close();
})();
