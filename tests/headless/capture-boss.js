const puppeteer = require('puppeteer-core');
const fs = require('fs');

const url = process.argv[2];
const mode = Number(process.argv[3]);   // 4 = ray, 5 = voxel
const outDir = process.argv[4];
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: 'new',
    args: ['--no-sandbox', '--disable-gpu', '--window-size=1240,720', '--autoplay-policy=no-user-gesture-required'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1240, height: 720 });
  await page.evaluateOnNewDocument((m) => {
    localStorage.clear();
    localStorage.setItem('BossMan.mazeZoom', String(m));
  }, mode);
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
  await sleep(3500);
  await page.click('canvas');
  await page.keyboard.press('Space');
  await sleep(2500);

  // roam: forward bursts with turns so bosses enter hunt range, snapping continuously
  let frame = 0;
  const snap = async () => { await page.screenshot({ path: `${outDir}/f${String(frame++).padStart(3, '0')}.png` }); };
  if (process.argv[5] === 'catch') {
    // roam aggressively (the pattern that organically produces catches) with
    // dense snaps; the frames just before a life drop hold the landing size
    const moves = ['ArrowUp', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'ArrowUp', 'ArrowLeft'];
    while (frame < 160) {
      for (const key of moves) {
        await page.keyboard.down(key);
        const hold = key === 'ArrowUp' ? 1600 : 480;
        const t0 = Date.now();
        while (Date.now() - t0 < hold) { await snap(); await sleep(300); }
        await page.keyboard.up(key);
        if (frame >= 160) break;
      }
    }
    console.log(`captured ${frame} frames -> ${outDir} (catch mode)`);
    await browser.close();
    return;
  }
  if (process.argv[5] === 'catch') {
    // walk the deterministic opening, then hold still so the nearest boss
    // closes in and catches Pete; dense snaps around the catch moment
    await page.keyboard.down('ArrowUp'); await sleep(2800); await page.keyboard.up('ArrowUp');
    for (let i = 0; i < 90; i++) { await snap(); await sleep(350); }
    console.log(`captured ${frame} frames -> ${outDir} (catch mode)`);
    await browser.close();
    return;
  }
  const pattern = ['ArrowUp', 'ArrowUp', 'ArrowRight', 'ArrowUp', 'ArrowUp', 'ArrowLeft', 'ArrowUp', 'ArrowDown', 'ArrowUp', 'ArrowRight'];
  for (let cycle = 0; cycle < 8 && frame < 110; cycle++) {
    for (const key of pattern) {
      await page.keyboard.down(key);
      const hold = key === 'ArrowUp' ? 1400 : 480;
      const t0 = Date.now();
      while (Date.now() - t0 < hold) { await snap(); await sleep(420); }
      await page.keyboard.up(key);
      if (frame >= 110) break;
    }
  }
  console.log(`captured ${frame} frames -> ${outDir}`);
  await browser.close();
})().catch(e => { console.error('FAILED:', e.message); process.exit(1); });
