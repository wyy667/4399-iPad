// Read-only, best-effort live integration probe. Not a substitute for iPad testing.
const { webkit } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const resource = path.join(root, 'Flash4399/WebAssets');
(async () => {
  const browser = await webkit.launch();
  try {
    const context = await browser.newContext({ viewport: { width: 1366, height: 1024 },
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15' });
    await context.exposeFunction('readRuntimeChunk', ({name,offset}) => {
      if (!/^ruffle_web(?:-wasm_mvp)?_bg\.[A-Z0-9]+\.wasm$/.test(name)) throw Error('Invalid asset');
      const fd = fs.openSync(path.join(resource, 'Ruffle',name),'r');
      try { const b=Buffer.alloc(256*1024); const n=fs.readSync(fd,b,0,b.length,offset); return b.subarray(0,n).toString('base64'); }
      finally { fs.closeSync(fd); }
    });
    const gameCache = new Map();
    await context.exposeFunction('readGameChunk', async ({url,offset}) => {
      const parsed = new URL(url);
      if (!['sda.4399.com','www.4399.com'].includes(parsed.hostname) || !/^\/(4399swf|upload_swf)\//.test(parsed.pathname)) throw Error('Invalid game URL');
      if (!gameCache.has(url)) gameCache.set(url, (async () => {
        const response = await fetch(url, { headers: { Referer: 'https://www.4399.com/' } });
        if (!response.ok) throw Error('Asset HTTP ' + response.status);
        const data = Buffer.from(await response.arrayBuffer());
        if (data.length > 64*1024*1024) throw Error('Asset too large');
        return { data, mime: response.headers.get('content-type') || 'application/octet-stream' };
      })());
      const result = await gameCache.get(url);
      return {data:result.data.subarray(offset,offset+256*1024).toString('base64'),mime:result.mime};
    });
    await context.addInitScript({content: 'window.webkit={messageHandlers:{runtimeAsset:{postMessage:body=>window.readRuntimeChunk(body)},gameAsset:{postMessage:body=>window.readGameChunk(body)}}};\n' +
      ['bootstrap.js','Ruffle/ruffle.js','input.js'].map(n=>fs.readFileSync(path.join(resource,n),'utf8')).join('\n;\n')});
    const page = await context.newPage();
    await context.route(/^https?:\/\/www\.4399\.com\/jss\/flashopen1\.js(?:\?.*)?$/, route => route.abort());
    const errors = [], swfs = [];
    page.on('console', m=> { if(m.type()==='error')errors.push(m.text().slice(0,400)); });
    page.on('response', r=> {if(/\.swf(?:\?|$)/i.test(r.url()))swfs.push({url:r.url(),status:r.status()});});
    const url=process.argv[2] || 'https://www.4399.com/flash/113110.htm';
    await page.goto(url,{waitUntil:'domcontentloaded',timeout:45000});
    const start = page.locator('.intr-l .play a.btn');
    const popupPromise = page.waitForEvent('popup', { timeout: 5000 }).catch(() => null);
    await start.click({ timeout: 15000 });
    const popup = await popupPromise;
    if (popup) {
      await popup.waitForLoadState('domcontentloaded');
      const destination = popup.url();
      await popup.close();
      await page.goto(destination, { waitUntil: 'domcontentloaded', timeout: 45000 });
    }
    await page.waitForTimeout(15000);
    const frames=[];
    for(const frame of page.frames()) {
      try {frames.push(await frame.evaluate(()=>({url:location.href,players:[...document.querySelectorAll('ruffle-object,ruffle-embed,ruffle-player')].map(el=>({metadata:el.ruffle().metadata,html:el.outerHTML.slice(0,500)}))})));}catch{}
    }
    fs.mkdirSync(path.join(root,'artifacts'),{recursive:true});
    await page.screenshot({path:path.join(root,'artifacts/live-4399.png')});
    const report={url:page.url(),title:await page.title(),frames,swfs,errors:[...new Set(errors)].slice(0,30)};
    fs.writeFileSync(path.join(root,'artifacts/live-4399.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify(report,null,2));
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
