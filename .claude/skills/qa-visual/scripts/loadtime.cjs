// Usage: node loadtime.cjs <url> [label]
// Throttles the network (default 8 Mbps / 60 ms RTT; env MBPS, RTT), screenshots
// the page at 300 ms and 2 s, and reports when the app hook is ready (#10).
const { chromium } = require('playwright');
(async () => {
  const [url, label = 'run'] = process.argv.slice(2);
  const mbps = +(process.env.MBPS || 8), rtt = +(process.env.RTT || 60);
  const out = process.env.OUT || '/tmp';
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false, latency: rtt, downloadThroughput: mbps * 125000, uploadThroughput: mbps * 125000,
  });
  const t0 = Date.now();
  page.goto(url).catch(() => {});
  await page.waitForTimeout(300);
  await page.screenshot({ path: `${out}/${label}-300ms.png` });
  await page.waitForTimeout(1700);
  await page.screenshot({ path: `${out}/${label}-2s.png` });
  await page.waitForFunction(() => window.__tileCity, null, { timeout: 180000, polling: 100 });
  const ready = Date.now() - t0;
  await page.waitForTimeout(1500);
  const loaderGone = await page.evaluate(() => !document.getElementById('loader'));
  console.log(`${label}: app ready after ${(ready / 1000).toFixed(1)} s at ${mbps} Mbps; loader removed: ${loaderGone}`);
  await browser.close();
})();
