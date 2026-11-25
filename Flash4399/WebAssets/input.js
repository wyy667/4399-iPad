(() => {
  'use strict';
  const players = 'ruffle-player, ruffle-object, ruffle-embed';
  const held = new Map();
  let activePlayer = null;
  // WebKit can initialize Ruffle against an iframe's initial empty document.
  // Re-scan at the final document's ready event if native Flash embeds remain.
  function finishPolyfill() {
    if (document.querySelector('object[type="application/x-shockwave-flash"], embed[type="application/x-shockwave-flash"], object[data$=".swf"], embed[src$=".swf"]')) {
      window.RufflePlayer?.newest()?.polyfill();
    }
  }
  if (document.readyState === 'loading') {
    window.addEventListener('DOMContentLoaded', finishPolyfill, { once: true });
    window.addEventListener('load', finishPolyfill, { once: true });
  } else finishPolyfill();
  function playerFrom(event) {
    return event.composedPath().find(node => node instanceof Element && node.matches(players));
  }
  document.addEventListener('pointerdown', event => {
    activePlayer = playerFrom(event) || null;
    if (activePlayer) {
      if (!activePlayer.hasAttribute('tabindex')) activePlayer.tabIndex = 0;
      activePlayer.focus({ preventScroll: true });
    } else release();
  }, true);
  document.addEventListener('focusin', event => {
    if (!playerFrom(event)) { release(); activePlayer = null; }
  });
  document.addEventListener('keydown', event => {
    if (!activePlayer?.isConnected || event.metaKey || event.ctrlKey || event.altKey) return;
    if (event.composedPath().some(node => node instanceof Element &&
        (node.matches('input, textarea, select') || node.isContentEditable))) return;
    held.set(event.code, { key: event.key, code: event.code, keyCode: event.keyCode,
      which: event.which, location: event.location, target: event.target });
    // Preserve the trusted event for Ruffle; only prevent browser scrolling.
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(event.code)) event.preventDefault();
  }, true);
  document.addEventListener('keyup', event => held.delete(event.code), true);
  function release() {
    for (const data of [...held.values()]) {
      const { target, ...init } = data;
      (target?.isConnected ? target : document).dispatchEvent(new KeyboardEvent('keyup', {
        ...init, bubbles: true, composed: true
      }));
    }
    held.clear();
  }
  window.addEventListener('blur', release);
  document.addEventListener('visibilitychange', () => { if (document.hidden) release(); });
  window.addEventListener('message', event => {
    if (event.source !== window && event.source !== window.parent) return;
    if (event.data?.type !== 'flash4399-release-input') return;
    release();
    for (const frame of document.querySelectorAll('iframe')) {
      frame.contentWindow?.postMessage({ type: 'flash4399-release-input' }, '*');
    }
  });
})();
