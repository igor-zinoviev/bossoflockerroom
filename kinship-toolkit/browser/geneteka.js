// Geneteka (польське ТГ): пошук у народженнях/шлюбах/смертях. Один запит на тип, з паузою — без обходу обмежень.
// node browser/geneteka.js <воєводство-код, напр. 21uk> <прізвище> [від] [до] [exac]
const { chromium } = require('playwright');
const [,, w, surname, from, to, exac] = process.argv;
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  for (const bdm of ['B', 'S', 'D']) {
    const u = `https://geneteka.genealodzy.pl/index.php?op=gt&lang=pol&bdm=${bdm}&w=${w}&rid=B&search_lastname=${encodeURIComponent(surname)}&search_name=&search_lastname2=&search_name2=&from_date=${from || ''}&to_date=${to || ''}${exac ? '&exac=1' : ''}`;
    try {
      await p.goto(u, { timeout: 60000, waitUntil: 'networkidle' });
      await p.waitForTimeout(2500);
      const rows = await p.evaluate((id) => {
        const t = document.getElementById(id); if (!t) return ['(no table)'];
        return [...t.rows].map(tr => [...tr.children].map(td => td.innerText.trim().replace(/\s+/g, ' ')).join(' | '));
      }, 'table_' + bdm.toLowerCase());
      console.log(`### ${bdm} "${surname}" ${w} rows=${rows.length - 1}`);
      console.log(rows.slice(0, 45).join('\n'));
    } catch (e) { console.log('ERR', bdm, e.message.slice(0, 120)); }
    await p.waitForTimeout(2000);
  }
  await b.close();
})();
