const puppeteer = require('puppeteer-core');
const fs = require('fs');

const url = process.argv[2];
const outDir = process.argv[3] || '.';
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
const MODES_ALL = [
  { n: 0, name: 'wide',  label: 'LUMBERGH',   kind: '2d' },
  { n: 1, name: 'zoom',  label: 'TWO BOBS',   kind: '2d' },
  { n: 2, name: 'macro', label: 'MILTON',     kind: '2d' },
  { n: 3, name: 'iso',   label: 'WONDERLAND', kind: 'grid3d' },
  { n: 4, name: 'ray',   label: 'SEVERANCE',  kind: 'fps' },
  { n: 5, name: 'voxel', label: 'LABYRINTH',  kind: 'fps' },
];

const MODES = ONLY ? MODES_ALL.filter(m => ONLY.includes(m.name)) : MODES_ALL;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function play2d(page) {
  const dirs = ['ArrowRight', 'ArrowUp', 'ArrowLeft', 'ArrowDown', 'ArrowRight', 'ArrowUp', 'ArrowRight', 'ArrowDown'];
  for (const d of dirs) {
    await page.keyboard.down(d);
    await sleep(1300);
    await page.keyboard.up(d);
    if (Math.random() < 0.4) await page.keyboard.press('Space');
  }
}

async function playFps(page) {
  for (let i = 0; i < 3; i++) {
    await page.keyboard.down('ArrowUp');   await sleep(1800); await page.keyboard.up('ArrowUp');
    await page.keyboard.press('Space');
    await page.keyboard.down('ArrowRight'); await sleep(500);  await page.keyboard.up('ArrowRight');
    await page.keyboard.down('ArrowUp');   await sleep(1400); await page.keyboard.up('ArrowUp');
    // regression: backward must reverse only while held, never latch
    await page.keyboard.down('ArrowDown'); await sleep(1500); await page.keyboard.up('ArrowDown');
    await page.keyboard.down('ArrowLeft'); await sleep(450);  await page.keyboard.up('ArrowLeft');
    await page.keyboard.press('Space');
  }
}

(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: 'new',
    args: ['--no-sandbox', '--disable-gpu', '--window-size=1240,720', '--autoplay-policy=no-user-gesture-required'],
  });

  const report = [];
  for (const m of MODES) {
    const page = await browser.newPage();
    await page.setViewport({ width: 1240, height: 720 });
    const errors = [];
    page.on('console', (msg) => {
      const t = msg.text();
      if (/error|trap|unreachable|RuntimeError|threw|NaN|undefined is not/i.test(t) && !/AudioContext/i.test(t)) errors.push(t.slice(0, 200));
    });
    page.on('pageerror', (e) => errors.push('PAGEERROR ' + e.message.slice(0, 200)));

    await page.evaluateOnNewDocument((mode) => {
      localStorage.clear();
      localStorage.setItem('BossMan.mazeZoom', String(mode));
    }, m.n);

    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(3500);
    await page.screenshot({ path: `${outDir}/${m.name}-0title.png` });

    await page.click('canvas');
    await page.keyboard.press('Space');
    await sleep(2500);
    await page.screenshot({ path: `${outDir}/${m.name}-1start.png` });

    if (m.kind === 'fps') await playFps(page); else await play2d(page);
    await page.screenshot({ path: `${outDir}/${m.name}-2mid.png` });

    if (m.kind === 'fps') await playFps(page); else await play2d(page);
    await page.screenshot({ path: `${outDir}/${m.name}-3end.png` });

    // freeze probe: all keys up, world should still animate (bosses/HUD)
    const a = await page.screenshot({ encoding: 'binary' });
    await sleep(1600);
    const b = await page.screenshot({ encoding: 'binary' });
    const frozen = Buffer.compare(a, b) === 0;

    report.push({ mode: m.name, label: m.label, errors, frozen });
    console.log(`${m.name.padEnd(6)} errors=${errors.length} frozen=${frozen}${errors.length ? '  | ' + errors[0] : ''}`);
    await page.close();
  }

  fs.writeFileSync(`${outDir}/modes-report.json`, JSON.stringify(report, null, 2));
  await browser.close();
})().catch(e => { console.error('DRIVER FAILED:', e.message); process.exit(1); });
