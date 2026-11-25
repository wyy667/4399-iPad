(() => {
  'use strict';
  if (window.__flash4399Bootstrap) return;
  window.__flash4399Bootstrap = true;
  const prefix = 'https://ruffle-bundle.invalid/';
  const allowed = new Set(['ruffle_web_bg.QDRSAAAZ.wasm', 'ruffle_web-wasm_mvp_bg.UMWKJ7EM.wasm']);
  const nativeFetch = window.fetch.bind(window);
  const trustedHost = host => ['4399.com', '5054399.com'].some(domain => host === domain || host.endsWith('.' + domain));
  async function gameFetch(url, signal) {
    const handler = window.webkit.messageHandlers.gameAsset;
    let offset = 0;
    let first = await handler.postMessage({ url, offset });
    const mime = first.mime;
    const response = new Response(new ReadableStream({
      async pull(controller) {
        try {
          if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
          const result = first || await handler.postMessage({ url, offset });
          first = null;
          const binary = atob(result.data);
          if (!binary.length) { controller.close(); return; }
          const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
          offset += bytes.length;
          controller.enqueue(bytes);
        } catch (error) { controller.error(error); }
      }
    }), { headers: { 'Content-Type': mime } });
    Object.defineProperty(response, 'url', { value: url });
    return response;
  }
  // Feed WASM from the App bundle. No HTTP server, CDN or remote execution.
  // Chunking avoids a single ~20 MB base64 message on the main thread.
  window.fetch = async function (input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (!url?.startsWith(prefix)) {
      try { return await nativeFetch(input, init); }
      catch (error) {
        const asset = new URL(url, location.href);
        const method = init?.method || input?.method || 'GET';
        const signal = init?.signal || input?.signal;
        if (signal?.aborted || method.toUpperCase() !== 'GET' || !trustedHost(location.hostname) ||
            !trustedHost(asset.hostname) || asset.protocol !== 'https:' ||
            !/^\/(4399swf|upload_swf)\//i.test(asset.pathname)) throw error;
        return gameFetch(asset.href, signal);
      }
    }
    const name = url.slice(prefix.length);
    if (!allowed.has(name)) throw new Error('Unknown bundled runtime asset');
    let offset = 0;
    const signal = init?.signal || input?.signal;
    return new Response(new ReadableStream({
      async pull(controller) {
        try {
          if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
          const encoded = await window.webkit.messageHandlers.runtimeAsset.postMessage({ name, offset });
          const binary = atob(encoded);
          if (!binary.length) { controller.close(); return; }
          const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
          offset += bytes.length;
          controller.enqueue(bytes);
        } catch (error) { controller.error(error); }
      }
    }), { headers: { 'Content-Type': 'application/wasm' } });
  };
  window.RufflePlayer = window.RufflePlayer || {};
  window.RufflePlayer.config = {
    ...window.RufflePlayer.config,
    publicPath: prefix,
    polyfills: true,
    favorFlash: false,
    autoplay: 'auto',
    unmuteOverlay: 'visible',
    // 4399's Flash detection and loaders use ExternalInterface callbacks.
    // Enable page interaction only on the intended site and its asset domain.
    allowScriptAccess: ['4399.com', '5054399.com'].some(domain =>
      location.hostname === domain || location.hostname.endsWith('.' + domain)),
    logLevel: 'warn'
  };
})();
