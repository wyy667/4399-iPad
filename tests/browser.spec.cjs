const { test, expect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { PNG } = require('pngjs');
const root = path.resolve(__dirname, '..');
const resources = path.join(root, 'Flash4399/Resources');
let server, base;

test.beforeAll(async () => {
  server = http.createServer((req, res) => {
    if (req.url === '/smoke.swf') {
      res.setHeader('Content-Type', 'application/x-shockwave-flash');
      return res.end(fs.readFileSync(path.join(__dirname, 'smoke.swf')));
    }
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    if (req.url === '/dynamic') return res.end('<!doctype html><body><input id="text"><div style="height:2000px"></div>');
    if (req.url === '/frames') return res.end('<!doctype html><iframe src="/selftest" width="900" height="800"></iframe>');
    res.end(fs.readFileSync(path.join(resources, 'selftest.html')));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
test.afterAll(async () => { await new Promise(resolve => server.close(resolve)); });

test.beforeEach(async ({ page }) => {
  page.on('pageerror', error => console.log('PAGE ERROR:', error.message));
  await page.exposeFunction('readRuntimeChunk', ({ name, offset }) => {
    expect(['ruffle_web_bg.QDRSAAAZ.wasm', 'ruffle_web-wasm_mvp_bg.UMWKJ7EM.wasm']).toContain(name);
    const fd = fs.openSync(path.join(resources, 'Ruffle', name), 'r');
    try {
      const buffer = Buffer.alloc(256 * 1024);
      const length = fs.readSync(fd, buffer, 0, buffer.length, offset);
      return buffer.subarray(0, length).toString('base64');
    } finally { fs.closeSync(fd); }
  });
  await page.addInitScript(() => {
    window.webkit = { messageHandlers: { runtimeAsset: { postMessage: body => window.readRuntimeChunk(body) } } };
  });
  // One init script preserves the same explicit ordering as WKUserScripts.
  await page.addInitScript({ content: ['bootstrap.js', 'Ruffle/ruffle.js', 'input.js']
    .map(file => fs.readFileSync(path.join(resources, file), 'utf8')).join('\n;\n') });
});

test('bundled WASM renders an original SWF without downloading the runtime', async ({ page }, testInfo) => {
  const externalRuntime = [];
  page.on('request', req => { if (/ruffle-bundle|\.wasm/.test(req.url())) externalRuntime.push(req.url()); });
  await page.goto(base + '/selftest');
  const player = page.locator('ruffle-object');
  await expect(player).toHaveCount(1);
  await expect.poll(() => player.evaluate(el => el.ruffle().metadata?.width), { timeout: 60000 }).toBe(320);
  await player.click({ position: { x: 20, y: 20 } });
  // Headless Chromium uses software rendering and shows an informational modal.
  const accelerationClose = player.locator('#hardware-acceleration-modal .close-modal');
  if (await accelerationClose.isVisible()) await accelerationClose.click();
  await expect.poll(async () => {
    const png = PNG.sync.read(await player.screenshot());
    let green = 0, blue = 0;
    for (let i = 0; i < png.data.length; i += 4) {
      const [r,g,b] = png.data.subarray(i,i+3);
      if (g > 160 && r < 100 && b < 170) green++;
      if (r < 40 && g >= 25 && g < 70 && b >= 55 && b < 100) blue++;
    }
    return green > 1000 && blue > 10000;
  }, { timeout: 30000 }).toBe(true);
  await player.screenshot({ path: testInfo.outputPath('rendered-swf.png') });
  const greenCenter = async () => {
    const png = PNG.sync.read(await player.screenshot());
    let sum = 0, count = 0;
    for (let i = 0; i < png.data.length; i += 4) {
      const [r,g,b] = png.data.subarray(i,i+3);
      if (g > 160 && r < 100 && b < 170) { sum += (i / 4) % png.width; count++; }
    }
    return count ? sum / count : -1;
  };
  const initialCenter = await greenCenter();
  await page.keyboard.down('d');
  await expect.poll(greenCenter).toBeGreaterThan(initialCenter + 100);
  await page.keyboard.up('d');
  await expect.poll(async () => Math.abs(await greenCenter() - initialCenter)).toBeLessThan(3);
  expect(externalRuntime).toEqual([]);
});

test('dynamic Flash embeds, keyboard focus and release preserve normal text entry', async ({ page }) => {
  await page.goto(base + '/dynamic');
  await page.evaluate(() => {
    const embed = document.createElement('embed');
    embed.type = 'application/x-shockwave-flash'; embed.src = '/smoke.swf';
    embed.width = '320'; embed.height = '240'; document.body.prepend(embed);
  });
  const player = page.locator('ruffle-embed');
  await expect(player).toHaveCount(1);
  await expect.poll(() => player.evaluate(el => el.ruffle().metadata?.width), { timeout: 60000 }).toBe(320);
  await player.click({ position: { x: 20, y: 20 } });
  await page.evaluate(() => {
    window.released = [];
    document.addEventListener('keyup', e => { if (!e.isTrusted) window.released.push(e.code); });
  });
  await page.keyboard.down('ArrowDown');
  await page.keyboard.down('j');
  expect(await page.evaluate(() => scrollY)).toBe(0);
  await page.evaluate(() => window.postMessage({ type: 'flash4399-release-input' }, '*'));
  await expect.poll(() => page.evaluate(() => window.released)).toEqual(expect.arrayContaining(['ArrowDown', 'KeyJ']));
  await page.keyboard.up('ArrowDown'); await page.keyboard.up('j');
  await page.locator('#text').fill('WASD normal input');
  await expect(page.locator('#text')).toHaveValue('WASD normal input');
});

test('Flash replacement also runs inside frames', async ({ page }) => {
  await page.goto(base + '/frames');
  const player = page.frameLocator('iframe').locator('ruffle-object');
  await expect(player).toHaveCount(1);
  await expect.poll(() => player.evaluate(el => el.ruffle().metadata?.width), { timeout: 60000 }).toBe(320);
});

test('legacy game CDN can fall back to the bounded native asset bridge', async ({ page }) => {
  const asset = 'https://sda.4399.com/4399swf/test.swf';
  const requests = [];
  await page.exposeFunction('readGameChunk', body => {
    requests.push(body);
    expect(body.url).toBe(asset);
    const bytes = fs.readFileSync(path.join(__dirname, 'smoke.swf'));
    return { data: bytes.subarray(body.offset, body.offset + 256 * 1024).toString('base64'), mime: 'application/x-shockwave-flash' };
  });
  await page.addInitScript(() => {
    // Install after existing init scripts regardless of their execution order.
    document.addEventListener('DOMContentLoaded', () => {
      window.webkit.messageHandlers.gameAsset = { postMessage: body => window.readGameChunk(body) };
      const embed = document.createElement('embed');
      embed.type = 'application/x-shockwave-flash';
      embed.src = 'https://sda.4399.com/4399swf/test.swf';
      document.body.appendChild(embed);
    });
  });
  await page.route('https://www.4399.com/native-test', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><body></body>' }));
  await page.route(asset, route => route.abort());
  await page.goto('https://www.4399.com/native-test');
  const player = page.locator('ruffle-embed');
  await expect.poll(() => player.evaluate(el => el.ruffle().metadata?.width), { timeout: 60000 }).toBe(320);
  expect(requests.length).toBeGreaterThan(0);
  const before = requests.length;
  await page.route('https://example.com/private.swf', route => route.abort());
  expect(await page.evaluate(() => fetch('https://example.com/private.swf').then(() => false, () => true))).toBe(true);
  expect(requests.length).toBe(before);
});
