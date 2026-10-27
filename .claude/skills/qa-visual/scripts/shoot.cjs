// Usage: node shoot.cjs <url> <outDir> '[["name","js"], ...]'
// Each step runs `js` in the page with helper c(obj) = __tileCity.cmd(obj),
// waits WAIT ms (default 1500) and saves <outDir>/<name>.png. Also supports
// mouse steps: ["name", "@click x y"], ["name", "@drag x y dx dy"], ["name", "@wheel dy"],
// ["name", "@hold x y"] (long press), ["name", "@reload"], ["name", "@goto <url>"].
// Env: W, H (viewport), WAIT.
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [url, out, stepsJson] = process.argv.slice(2);
  const steps = JSON.parse(stepsJson || '[["shot",""]]');
  const W = +(process.env.W || 1440), H = +(process.env.H || 860), WAIT = +(process.env.WAIT || 1500);
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  page.on('console', (m) => { if (m.type() === 'error') console.log('console error:', m.text().slice(0, 300)); });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__tileCity, null, { timeout: 60000 }).catch(() => console.log('no __tileCity hook (build with --dart-define=DEBUG_HOOK=true)'));
  await page.waitForTimeout(3000);
  for (const [name, js] of steps) {
    if (js.startsWith('@')) {
      const [cmd, ...a] = js.slice(1).split(' ').map((x, i) => (i ? +x : x));
      // (for @goto the URL is read from js directly)
      if (cmd === 'click') await page.mouse.click(a[0], a[1]);
      if (cmd === 'drag') { await page.mouse.move(a[0], a[1]); await page.mouse.down(); await page.mouse.move(a[0] + a[2], a[1] + a[3], { steps: 8 }); await page.mouse.up(); }
      if (cmd === 'wheel') { await page.mouse.move(W / 2, H / 2); await page.mouse.wheel(0, a[0]); }
      if (cmd === 'reload' || cmd === 'goto') {
        // "@reload" keeps localStorage; "@goto <url>" opens another URL (share links).
        if (cmd === 'reload') await page.reload({ waitUntil: 'load' });
        else await page.goto(js.slice(6).trim(), { waitUntil: 'load' });
        await page.waitForFunction(() => window.__tileCity, null, { timeout: 60000 });
        await page.waitForTimeout(3000);
      }
      if (cmd === 'hold') { await page.mouse.move(a[0], a[1]); await page.mouse.down(); await page.waitForTimeout(700); await page.mouse.up(); }
    } else if (js) {
      const r = await page.evaluate((code) => {
        const c = (o) => JSON.parse(window.__tileCity.cmd(JSON.stringify(o)));
        return JSON.stringify(new Function('c', code)(c) ?? null);
      }, js);
      if (r && r !== 'null') console.log(name, '→', r.slice(0, 400));
    }
    await page.waitForTimeout(WAIT);
    await page.screenshot({ path: `${out}/${name}.png` });
    console.log('saved', `${out}/${name}.png`);
  }
  await browser.close();
})();
