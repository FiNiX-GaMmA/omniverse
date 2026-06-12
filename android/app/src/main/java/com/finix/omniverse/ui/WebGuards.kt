package com.finix.omniverse.ui

import android.net.Uri

/// Ad-host blocking + JS guard payloads, ported from the iOS WebEmbed /
/// VidsrcResolve screens. Kept in one place so screens stay lean.
object WebGuards {

    private val blockedHosts = listOf(
        "google-analytics.com", "analytics.google.com", "googletagmanager.com", "googletagservices.com",
        "doubleclick.net", "*.doubleclick.net", "adservice.google.com", "pagead2.googlesyndication.com",
        "stats.g.doubleclick.net", "cdn.adx1.com", "intelligenceadx.com", "adsco.re", "mc.yandex.com",
        "mc.yandex.ru", "bvtpk.com", "my.rtmark.net", "b7510.com", "gt.unbrownunflat.com",
        "im.malocacomals.com", "users.videasy.net", "nf.sixmossin.com", "realizationnewestfangs.com",
        "acscdn.com", "static.cloudflareinsights.com", "usrpubtrk.com", "adexchangeclear.com",
    )

    fun shouldBlock(value: String): Boolean {
        var host = runCatching { Uri.parse(value).host?.lowercase() }.getOrNull() ?: return false
        if (host.startsWith("www.")) host = host.removePrefix("www.")
        return blockedHosts.any { pattern ->
            if (pattern.startsWith("*.")) host.endsWith(pattern.removePrefix("*"))
            else host == pattern || host.endsWith(".$pattern")
        }
    }

    /// Defeats iframe sandboxing (the "sandbox not allowed — remove sandbox from
    /// iframe to play" blocker). Overrides setAttribute / the iframe sandbox
    /// setter, and strips+reloads any sandboxed iframe so it loads unsandboxed.
    /// Injected at onPageStarted (as early as possible) AND onPageFinished.
    val unsandboxJs: String = """
(function () {
  if (window.__omniplayUnsandbox) return; window.__omniplayUnsandbox = true;
  try {
    var origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      try { if (name && String(name).toLowerCase() === 'sandbox') return; } catch (_) {}
      return origSetAttribute.apply(this, arguments);
    };
  } catch (_) {}
  try {
    var sandboxDesc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'sandbox');
    if (sandboxDesc && sandboxDesc.set) {
      Object.defineProperty(HTMLIFrameElement.prototype, 'sandbox', {
        configurable: true, enumerable: true,
        get: function () { try { return sandboxDesc.get.call(this); } catch (_) { return null; } },
        set: function () {}
      });
    }
  } catch (_) {}
  var unsandbox = function () {
    try {
      var frames = document.querySelectorAll('iframe[sandbox]');
      for (var i = 0; i < frames.length; i++) {
        var f = frames[i];
        if (f.getAttribute('data-omniplay-unsandboxed') === '1') { if (f.hasAttribute('sandbox')) { try { f.removeAttribute('sandbox'); } catch (_) {} } continue; }
        f.setAttribute('data-omniplay-unsandboxed', '1');
        try { f.removeAttribute('sandbox'); } catch (_) {}
        try { var src = f.getAttribute('src'); if (src) { f.setAttribute('src', 'about:blank'); f.setAttribute('src', src); } } catch (_) {}
      }
    } catch (_) {}
  };
  unsandbox();
  try { setInterval(unsandbox, 500); } catch (_) {}
  try { new MutationObserver(unsandbox).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['sandbox'] }); } catch (_) {}
})();
""".trimIndent()

    /// Injected on every WebEmbed page finish: blocks popups, strips ad iframes /
    /// scripts, neutralises window.open / location hijacks, fixes _blank anchors.
    val embedGuardJs: String = """
(() => {
  if (window.__omniplayGuards) return; window.__omniplayGuards = true;
  window.open = () => null; const noop = () => {};
  try { window.alert = noop; window.confirm = () => false; window.prompt = () => null; } catch (_) {}
  const safeHosts = ['vidsrc','cloudnestra','2embed','embed.su','autoembed','multiembed','rabbitstream','megacloud','streamtape','streamlare','doodstream','mixdrop','vidplay','filemoon','upstream','fembed','streamhide','mp4upload','streamsb','voe.sx','streamwish','vidcloud','youtube','cdn'];
  const isAdHost = (url) => { try { const h = new URL(url, location.href).hostname.toLowerCase(); return !safeHosts.some(s => h.includes(s)); } catch (_) { return false; } };
  try { const a = window.location.assign.bind(window.location); const r = window.location.replace.bind(window.location);
    window.location.assign = (u) => { if (!isAdHost(u)) a(u); }; window.location.replace = (u) => { if (!isAdHost(u)) r(u); }; } catch (_) {}
  const fixAnchors = () => document.querySelectorAll('a[target]').forEach(a => { const t = a.getAttribute('target'); if (t==='_blank'||t==='_top'||t==='_parent') a.removeAttribute('target'); });
  const adTokens = ['ads','ad-','analytics','doubleclick','googletagmanager','googletagservices','pagead','popunder','popcash','propellerads','adservice','adsco','rtmark','profitable','histats','usrpubtrk','adexchangeclear','realizationnewestfangs','unbrownunflat','sixmossin','malocacomals','cloudflareinsights','videasy','bvtpk','b7510','adx1','intelligenceadx','yandex','tmstr.'];
  const isAdSrc = (src) => { if (!src) return false; const s = String(src).toLowerCase(); return adTokens.some(t => s.includes(t)); };
  const stripAds = () => { document.querySelectorAll('iframe').forEach(f => { if (isAdSrc(f.src)) f.remove(); }); document.querySelectorAll('script').forEach(s => { if (isAdSrc(s.src)) s.remove(); }); fixAnchors(); };
  stripAds();
  try { new MutationObserver(stripAds).observe(document.documentElement, { childList: true, subtree: true }); } catch (_) {}
  document.addEventListener('click', (e) => { const a = e.target && e.target.closest && e.target.closest('a[href]'); if (a && isAdHost(a.href)) { e.preventDefault(); e.stopPropagation(); } }, true);
})();
""".trimIndent()

    /// Heavy guards + overlay-killer for the cloudnestra resolve flow.
    val vidsrcGuardJs: String = """
(function () {
  if (window.__omniplayGuards) return; window.__omniplayGuards = true;
  try { const st = document.createElement('style'); st.innerHTML = '* { outline: none !important; }'; document.documentElement.appendChild(st); } catch (_) {}
  try { window.open = function () { return null; }; } catch (_) {}
  const noop = function () {}; try { window.alert = noop; window.confirm = function(){return false;}; window.prompt = function(){return null;}; } catch (_) {}
  try { const o = window.addEventListener; window.addEventListener = function (t, l, op) { if (t==='beforeunload'||t==='unload') return; o.apply(this, arguments); }; } catch (_) {}
  const safeHosts = ['vidsrc','cloudnestra','vsembed','vsrc.','vidsrcme','about:','localhost','127.0.0.1','cdn','2embed','embed.su','autoembed','multiembed','rabbitstream','megacloud','streamtape','streamlare','doodstream','mixdrop','vidplay','filemoon','upstream','fembed','streamhide','mp4upload','streamsb','voe.sx','streamwish','vidcloud','youtube'];
  const isAdHost = function (url) { try { if (!url) return false; const h = new URL(url, location.href).hostname.toLowerCase(); return !safeHosts.some(function(s){return h.indexOf(s)>=0;}); } catch (_) { return false; } };
  const adTokens = ['ads','ad-','analytics','doubleclick','googletagmanager','googletagservices','pagead','popunder','popcash','propellerads','adservice','adsco','rtmark','profitable','histats','usrpubtrk','adexchangeclear','realizationnewestfangs','unbrownunflat','sixmossin','malocacomals','cloudflareinsights','videasy','bvtpk','b7510','adx1','intelligenceadx','yandex','tmstr.','click','track','redirect','pop'];
  const isAdSrc = function (src) { if (!src) return false; const s = String(src).toLowerCase(); if (safeHosts.some(function(h){return s.indexOf(h)>=0;})) return false; return adTokens.some(function(t){return s.indexOf(t)>=0;}); };
  try { const a = window.location.assign.bind(window.location); const r = window.location.replace.bind(window.location);
    window.location.assign = function(u){ if (!isAdHost(u)) a(u); }; window.location.replace = function(u){ if (!isAdHost(u)) r(u); }; } catch (_) {}
  const fixAnchors = function () { document.querySelectorAll('a[target]').forEach(function(a){ const t=a.getAttribute('target'); if (t==='_blank'||t==='_top'||t==='_parent') a.removeAttribute('target'); }); };
  const stripAds = function () { document.querySelectorAll('iframe').forEach(function(f){ if (isAdSrc(f.src)) f.remove(); }); document.querySelectorAll('script').forEach(function(s){ if (isAdSrc(s.src)) s.remove(); }); fixAnchors(); };
  stripAds();
  try { new MutationObserver(stripAds).observe(document.documentElement, { childList: true, subtree: true }); } catch (_) {}
  document.addEventListener('click', function (e) { const a = e.target && e.target.closest && e.target.closest('a[href]'); if (a && isAdHost(a.href)) { e.preventDefault(); e.stopPropagation(); } }, true);
  setInterval(function () { const divs = document.querySelectorAll('div'); const sw = window.innerWidth, sh = window.innerHeight;
    for (var i=0;i<divs.length;i++){ const d=divs[i]; const st=window.getComputedStyle(d); if (st.position==='absolute'||st.position==='fixed'){ const z=parseInt(st.zIndex,10); if (z>99){ const w=d.offsetWidth,h=d.offsetHeight; if (w>sw*0.5&&h>sh*0.5){ if (!d.querySelector('video, iframe, canvas, img') && d.innerText.trim().length<50) d.remove(); } } } } }, 500);
})();
""".trimIndent()

    val embedProbeJs: String = """
(function () {
  try {
    var html = document.documentElement.outerHTML || '';
    var iframeMatch = html.match(/<iframe[^>]+src=["']([^"']+)["']/i);
    var iframeSrc = iframeMatch ? iframeMatch[1] : '';
    var simpleRe = /data-hash=["']([^"']+)["']/g;
    var seen = {}, servers = [], m;
    var nameRe = /data-hash=["']([^"']+)["'][^>]*>([\s\S]*?)<\/div>/g;
    while ((m = nameRe.exec(html)) !== null) { var hash=m[1]; if (!hash||seen[hash]) continue; seen[hash]=true; var name=(m[2]||'').replace(/<[^>]*>/g,'').trim(); servers.push({name:name,hash:hash}); }
    if (servers.length === 0) { while ((m = simpleRe.exec(html)) !== null) { if (!seen[m[1]]) { seen[m[1]]=true; servers.push({name:'',hash:m[1]}); } } }
    var bodyText = (document.body && document.body.innerText) || '';
    var hasChallenge = /just a moment/i.test(document.title) || /cf-chl|cf_chl|checking your browser/i.test(bodyText) || /enable javascript and cookies/i.test(bodyText);
    return JSON.stringify({ title: document.title||'', url: location.href, iframeSrc: iframeSrc, servers: servers, hasChallenge: hasChallenge });
  } catch (e) { return JSON.stringify({ error: String(e) }); }
})();
""".trimIndent()

    val playerProbeJs: String = """
(function () {
  try {
    var hasPlayButton = !!document.querySelector('#pl_but,.fa-play,[id*=play]');
    var iframeLoaded = !!document.querySelector('iframe[src*="prorcp"], iframe#player_iframe');
    var bodyText = (document.body && document.body.innerText) || '';
    var hasChallenge = /just a moment/i.test(document.title) || /cf-chl|cf_chl|checking your browser/i.test(bodyText) || /enable javascript and cookies/i.test(bodyText);
    var hasTurnstile = !!document.querySelector('.cf-turnstile, [data-sitekey]');
    var hasRcpToken = /[?&]_rcp=/.test(location.href);
    return JSON.stringify({ title: document.title||'', url: location.href, hasPlayButton: hasPlayButton, iframeLoaded: iframeLoaded, hasChallenge: hasChallenge, hasTurnstile: hasTurnstile, hasRcpToken: hasRcpToken });
  } catch (e) { return JSON.stringify({ error: String(e) }); }
})();
""".trimIndent()

    const val clickPlayJs =
        "(function(){var b=document.querySelector('#pl_but,.fa-play,[id*=play]');if(b)b.click();})();"

    // Best-effort: scan the top document and any same-origin frames for a <video>
    // that has reached its end. Cross-origin frames throw on `.document` access and
    // are silently skipped (so this simply never fires for those players).
    val videoEndedProbeJs: String = """
(function () {
  function check(d) {
    try {
      var vids = d.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (v.duration > 0 && (v.ended || v.currentTime >= v.duration - 1.5)) return true;
      }
    } catch (e) {}
    return false;
  }
  var ended = false;
  try { if (check(document)) ended = true; } catch (e) {}
  if (!ended) {
    try {
      for (var i = 0; i < window.frames.length; i++) {
        try { if (window.frames[i].document && check(window.frames[i].document)) { ended = true; break; } } catch (e) {}
      }
    } catch (e) {}
  }
  return JSON.stringify({ ended: ended });
})();
""".trimIndent()
}
