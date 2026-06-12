import SwiftUI
import WebKit
import UIKit

// MARK: - Ad host blocking (ported 1:1 from _blockedHosts / _shouldBlock)

private let desktopUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

private let blockedHosts: [String] = [
    "google-analytics.com",
    "analytics.google.com",
    "googletagmanager.com",
    "googletagservices.com",
    "doubleclick.net",
    "*.doubleclick.net",
    "adservice.google.com",
    "pagead2.googlesyndication.com",
    "stats.g.doubleclick.net",
    "cdn.adx1.com",
    "intelligenceadx.com",
    "adsco.re",
    "mc.yandex.com",
    "mc.yandex.ru",
    "bvtpk.com",
    "my.rtmark.net",
    "b7510.com",
    "gt.unbrownunflat.com",
    "im.malocacomals.com",
    "users.videasy.net",
    "nf.sixmossin.com",
    "realizationnewestfangs.com",
    "acscdn.com",
    "static.cloudflareinsights.com",
    "usrpubtrk.com",
    "adexchangeclear.com",
]

private func shouldBlock(_ value: String) -> Bool {
    guard let url = URL(string: value), var host = url.host?.lowercased() else { return false }
    if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
    return blockedHosts.contains { pattern in
        if pattern.hasPrefix("*.") { return host.hasSuffix(String(pattern.dropFirst(1))) }
        return host == pattern || host.hasSuffix("." + pattern)
    }
}

// MARK: - Sandbox defeat (runs at documentStart in ALL frames)
//
// Defeats `sandbox` on the player iframe (the "sandbox not allowed — remove
// sandbox from iframe to play" blocker). Overrides setAttribute / the iframe
// sandbox setter, and strips+reloads any sandboxed iframe so it loads unsandboxed.

private let unsandboxJS = #"""
(function () {
  if (window.__omniplayUnsandbox) return;
  window.__omniplayUnsandbox = true;

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
        set: function () { /* ignore */ }
      });
    }
  } catch (_) {}

  var unsandbox = function () {
    try {
      var frames = document.querySelectorAll('iframe[sandbox]');
      for (var i = 0; i < frames.length; i++) {
        var f = frames[i];
        if (f.getAttribute('data-omniplay-unsandboxed') === '1') {
          if (f.hasAttribute('sandbox')) { try { f.removeAttribute('sandbox'); } catch (_) {} }
          continue;
        }
        f.setAttribute('data-omniplay-unsandboxed', '1');
        try { f.removeAttribute('sandbox'); } catch (_) {}
        try {
          var src = f.getAttribute('src');
          if (src) { f.setAttribute('src', 'about:blank'); f.setAttribute('src', src); }
        } catch (_) {}
      }
    } catch (_) {}
  };

  unsandbox();
  try { setInterval(unsandbox, 500); } catch (_) {}
  try {
    new MutationObserver(unsandbox).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['sandbox'] });
  } catch (_) {}
})();
"""#

// MARK: - Player guard JS (injected on didFinish — ported from _injectPlayerGuards)

private let webEmbedGuardJS = #"""
(() => {
  if (window.__omniplayGuards) return;
  window.__omniplayGuards = true;

  window.open = () => null;
  const noop = () => {};
  try { window.alert = noop; window.confirm = () => false; window.prompt = () => null; } catch (_) {}

  const safeHosts = [
    'vidsrc', 'cloudnestra', '2embed', 'embed.su', 'autoembed',
    'multiembed', 'rabbitstream', 'megacloud', 'streamtape',
    'streamlare', 'doodstream', 'mixdrop', 'vidplay', 'filemoon',
    'upstream', 'fembed', 'streamhide', 'mp4upload', 'streamsb',
    'voe.sx', 'streamwish', 'vidcloud', 'youtube', 'cdn'
  ];
  const isAdHost = (url) => {
    try {
      const host = new URL(url, location.href).hostname.toLowerCase();
      return !safeHosts.some((h) => host.includes(h));
    } catch (_) {
      return false;
    }
  };

  try {
    const origAssign = window.location.assign.bind(window.location);
    const origReplace = window.location.replace.bind(window.location);
    window.location.assign = (u) => { if (!isAdHost(u)) origAssign(u); };
    window.location.replace = (u) => { if (!isAdHost(u)) origReplace(u); };
  } catch (_) {}

  const fixAnchors = () => {
    document.querySelectorAll('a[target]').forEach((a) => {
      const t = a.getAttribute('target');
      if (t === '_blank' || t === '_top' || t === '_parent') a.removeAttribute('target');
    });
  };

  const adTokens = [
    'ads', 'ad-', 'analytics', 'doubleclick', 'googletagmanager',
    'googletagservices', 'pagead', 'popunder', 'popcash', 'propellerads',
    'adservice', 'adsco', 'rtmark', 'taloseempest', 'profitable',
    'preferencenail', 'protrafficinspector', 'histats', 'weirdopt',
    'usrpubtrk', 'adexchangeclear', 'realizationnewestfangs',
    'unbrownunflat', 'sixmossin', 'malocacomals', 'cloudflareinsights',
    'kettledroopingcontinuation', 'wayfarerorthodox', 'woxaglasuy',
    'adeptspiritual', 'calculating-laugh', 'amavhxdlofklxjg',
    'videasy', 'bvtpk', 'b7510', 'adx1', 'intelligenceadx', 'yandex',
    'tmstr4', 'tmstr.'
  ];
  const isAdSrc = (src) => {
    if (!src) return false;
    const s = String(src).toLowerCase();
    return adTokens.some((t) => s.includes(t));
  };

  const stripAds = () => {
    document.querySelectorAll('iframe').forEach((f) => { if (isAdSrc(f.src)) f.remove(); });
    document.querySelectorAll('script').forEach((s) => { if (isAdSrc(s.src)) s.remove(); });
    fixAnchors();
  };
  stripAds();

  const origCreate = document.createElement.bind(document);
  document.createElement = function (tag) {
    const el = origCreate(tag);
    const lower = String(tag).toLowerCase();
    if (lower === 'iframe' || lower === 'script') {
      const desc = Object.getOwnPropertyDescriptor(
        lower === 'iframe' ? HTMLIFrameElement.prototype : HTMLScriptElement.prototype,
        'src'
      );
      if (desc && desc.set) {
        Object.defineProperty(el, 'src', {
          configurable: true,
          enumerable: true,
          get() { return desc.get.call(this); },
          set(v) { if (!isAdSrc(v)) desc.set.call(this, v); },
        });
      }
    }
    return el;
  };

  try {
    new MutationObserver(stripAds).observe(document.documentElement, {
      childList: true, subtree: true,
    });
  } catch (_) {}

  document.addEventListener('click', (e) => {
    const a = e.target && e.target.closest && e.target.closest('a[href]');
    if (a && isAdHost(a.href)) { e.preventDefault(); e.stopPropagation(); }
  }, true);
})();
"""#

// MARK: - WKWebView wrapper

private struct EmbedWebView: UIViewRepresentable {
    let url: String
    let headers: [String: String]
    let onBlocked: () -> Void
    let onLoadingChanged: (Bool) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBlocked: onBlocked, onLoadingChanged: onLoadingChanged, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Defeat iframe sandboxing as early as possible, in every frame.
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: unsandboxJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        config.userContentController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = desktopUserAgent
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator

        // Header logic: explicit headers, else tv247.biz → Referer (ported).
        var req = URLRequest(url: URL(string: url) ?? URL(string: "about:blank")!)
        let effectiveHeaders: [String: String]
        if !headers.isEmpty {
            effectiveHeaders = headers
        } else if url.contains("tv247.biz") {
            effectiveHeaders = ["Referer": "https://tv247.biz/"]
        } else {
            effectiveHeaders = [:]
        }
        for (k, v) in effectiveHeaders { req.setValue(v, forHTTPHeaderField: k) }
        web.load(req)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onBlocked: () -> Void
        let onLoadingChanged: (Bool) -> Void
        let onError: (String) -> Void

        init(onBlocked: @escaping () -> Void, onLoadingChanged: @escaping (Bool) -> Void, onError: @escaping (String) -> Void) {
            self.onBlocked = onBlocked
            self.onLoadingChanged = onLoadingChanged
            self.onError = onError
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            let urlString = navigationAction.request.url?.absoluteString ?? ""
            // Block ad/popunder hosts only when they try to take over the top
            // frame. Subframe navigations (cloudnestra player iframe) allowed.
            if isMainFrame && shouldBlock(urlString) {
                onBlocked()
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChanged(false)
            webView.evaluateJavaScript(unsandboxJS) { _, _ in }
            webView.evaluateJavaScript(webEmbedGuardJS) { _, _ in }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingChanged(false)
            onError(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingChanged(false)
            onError(error.localizedDescription)
        }

        // Prevent window.open popups from opening a new web view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            return nil
        }
    }
}

// MARK: - WebEmbedPlayerScreen (public)

struct WebEmbedPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let title: String
    private let url: String
    private let headers: [String: String]
    private let item: MediaItem?

    @State private var loading = true
    @State private var blockedRequests = 0
    @State private var errorText: String?
    @State private var controlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?

    init(title: String, url: String, headers: [String: String] = [:], item: MediaItem? = nil) {
        self.title = title
        self.url = url
        self.headers = headers
        self.item = item
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            EmbedWebView(
                url: url,
                headers: headers,
                onBlocked: { blockedRequests += 1 },
                onLoadingChanged: { loading = $0; if !$0 { errorText = nil } },
                onError: { errorText = $0; loading = false }
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }

            if loading {
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)
            }

            if let errorText {
                Color.black.opacity(0.86).ignoresSafeArea()
                GlassPanel(cornerRadius: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.white)
                        Text("Could not open this server").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                        Text(errorText).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(40)
            }

            // Top control bar
            VStack {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }.buttonStyle(.plain)

                    Text(title).font(.system(size: 17, weight: .black)).foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()

                    GlassCapsule {
                        HStack(spacing: 8) {
                            Image(systemName: "shield").font(.system(size: 18))
                            Text("\(blockedRequests)")
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 10)
                Spacer()
            }
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .animation(.easeInOut(duration: 0.3), value: controlsVisible)
        }
        .statusBarHidden(true)
        .keepScreenAwake(true)
        .onAppear {
            PlayerOrientation.forceLandscape()
            startControlsTimer()
        }
        .onDisappear { PlayerOrientation.restore() }
    }

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible { startControlsTimer() } else { controlsHideTask?.cancel() }
    }

    private func startControlsTimer() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { controlsVisible = false }
        }
    }
}
