// Usage: node perf.cjs <url> [label]
// Measures frame timing in Chromium (swiftshader: compare runs, not absolutes)
// and reads the app's own CPU timings through window.__tileCity (DEBUG_HOOK build).
const { chromium } = require('playwright');
(async () => {
  const url = process.argv[2], label = process.argv[3] || url;
  const W = +(process.env.W || 1440), H = +(process.env.H || 860);
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__tileCity, null, { timeout: 60000 });
  await page.waitForTimeout(4000);
  const cmd = (o) => page.evaluate((j) => JSON.parse(window.__tileCity.cmd(j)), JSON.stringify(o));
  const measure = async (name, driver) => {
    const r = await page.evaluate(async (driver) => {
      const ts = [];
      let stop = false;
      const drive = driver ? new Function('c', driver) : null;
      const loop = (t) => { ts.push(t); if (drive) drive((o) => window.__tileCity.cmd(JSON.stringify(o))); if (!stop) requestAnimationFrame(loop); };
      requestAnimationFrame(loop);
      await new Promise((r) => setTimeout(r, 6000));
      stop = true;
      const d = []; for (let i = 1; i < ts.length; i++) d.push(ts[i] - ts[i - 1]);
      d.sort((a, b) => a - b);
      const s = JSON.parse(window.__tileCity.stats());
      return { fps: d.length / (d.reduce((a, b) => a + b, 0) / 1000), p50: d[d.length >> 1], p95: d[Math.floor(d.length * 0.95)], cpu: s.cpuMs, tris: s.triangles };
    }, driver);
    console.log(`${label.padEnd(10)} ${name.padEnd(22)} fps ${r.fps.toFixed(2).padStart(5)}  p50 ${r.p50.toFixed(0).padStart(4)} ms  p95 ${r.p95.toFixed(0).padStart(4)} ms  dart render ${r.cpu.toFixed(1).padStart(5)} ms  tris ${r.tris}`);
  };
  // PRE='[{"op":"smooth","v":false}]' applies commands before measuring.
  for (const o of JSON.parse(process.env.PRE || '[]')) await cmd(o);
  await cmd({ op: 'tilt', v: true });
  await measure('still, tilt-shift');
  await measure('orbiting, tilt-shift', "c({op:'orbit', v:[4,0]})");
  await measure('dragging Light', "window.__h=(window.__h||12)+0.05; if(window.__h>20) window.__h=8; c({op:'hour', v:window.__h})");
  await cmd({ op: 'hour', v: 17.6 });
  await cmd({ op: 'tilt', v: false });
  await measure('still, no tilt');
  await browser.close();
})();
