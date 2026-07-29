// ==============================================================================
// Omniverse Desktop — Safe Context Bridge & Webview Shield Preload
// ==============================================================================
// 1. If running in the main app window (file: or localhost), exposes secure
//    system bindings to the renderer under window.electron.
// 2. If running inside a guest webview, injects a defensive sandbox shield
//    to neutralize popup loops, click hijacking, and anti-debugging scripts.
// ==============================================================================

const { contextBridge, ipcRenderer } = require("electron");

const isMainApp =
  window.location.protocol === "file:" ||
  window.location.hostname === "localhost" ||
  window.location.protocol === "chrome-extension:" ||
  (window.location.protocol !== "http:" &&
    window.location.protocol !== "https:");

if (isMainApp) {
  // Expose secure API to the main application
  contextBridge.exposeInMainWorld("electron", {
    getPlatform: () => ipcRenderer.invoke("get-platform"),
    getArch: () => ipcRenderer.invoke("get-arch"),
    getAppVersion: () => ipcRenderer.invoke("get-app-version"),
    minimize: () => ipcRenderer.invoke("window-minimize"),
    maximize: () => ipcRenderer.invoke("window-maximize"),
    close: () => ipcRenderer.invoke("window-close"),
    openExternal: (url) => ipcRenderer.invoke("open-external", url),
    openPipWindow: (url, title) =>
      ipcRenderer.invoke("open-pip-window", { url, title }),
    closePipWindow: () => ipcRenderer.invoke("close-pip-window"),
    iptvFetch: (url, method = "GET", headers = {}, body = null) =>
      ipcRenderer.invoke("iptv-fetch", { url, method, headers, body }),
    syncPlayerCookies: () => ipcRenderer.invoke("sync-player-cookies"),
    playerStopped: () => ipcRenderer.invoke("player-stopped"),
    downloadUpdate: (url) => ipcRenderer.invoke("download-update-file", url),
    onUpdateProgress: (cb) => {
      const handler = (_, pct) => cb(pct);
      ipcRenderer.on("update-progress", handler);
      return () => ipcRenderer.removeListener("update-progress", handler);
    },
    getAdShieldStats: () => ipcRenderer.invoke("get-adshield-stats"),
    clearCache: () => ipcRenderer.invoke("clear-cache"),
    showNotification: (title, body) =>
      ipcRenderer.invoke("show-notification", { title, body }),
    onAdShieldStats: (cb) => {
      const handler = (_, stats) => cb(stats);
      ipcRenderer.on("adshield-stats", handler);
      return () => ipcRenderer.removeListener("adshield-stats", handler);
    },
    onWebviewFullscreen: (cb) => {
      const handler = (_, state) => cb(state);
      ipcRenderer.on("webview-fullscreen", handler);
      return () => ipcRenderer.removeListener("webview-fullscreen", handler);
    },
    onWebviewLoadFailed: (cb) => {
      const handler = (_, info) => cb(info);
      ipcRenderer.on("webview-load-failed", handler);
      return () => ipcRenderer.removeListener("webview-load-failed", handler);
    },

  });
} else {
  // Guest Webview Context: Inject a client-side defensive shield to block redirects and popups
  try {
    const shieldScript = () => {
      // Stub out window.open immediately
      window.open = function () {
        console.log("[Omniverse Shield] Blocked window.open popup attempt.");
        return {
          focus: () => {},
          blur: () => {},
          close: () => {},
          closed: true,
        };
      };

      // Disable common devtool protectors (like disable-devtool.js)
      Object.defineProperty(window, "disableDevtool", {
        value: {
          isopen: false,
          ondevtoolopen: () => {},
          close: () => {},
          md5: () => "",
          version: "1.0.0",
        },
        writable: false,
        configurable: false,
        enumerable: true,
      });

      // Break loop alerts or prompt hijacks
      window.alert = (msg) =>
        console.log("[Omniverse Shield] Blocked alert-box: " + msg);
      window.confirm = () => true;
      window.prompt = () => "";

      const trustedPlaybackHosts = [
        "vsembed.ru",
        "vsembed.su",
        "little-field-fe85.instafashion662-3d4.workers.dev",
        "instafashion662-3d4.workers.dev",
        "workers.dev",
        "ferocitycandour.com",
        "cinezo",
        "notyourtype.dad",
        "ballerinacappuccinalovestungtungtungsahur.com",
        "1shows.app",
        "5-ac2.workers.dev",
        "solitary-paper",
        "pinepathcreativecollect",
        "remoteconsultinggroup",
        "nextgencloudfabric",
        "vidsrc.me",
        "vidsrc.to",
        "vidsrc.pro",
        "vidsrc.vip",
        "vidsrc.net",
        "vidsrc.cc",
        "vidsrc.xyz",
        "vidsrc-embed.ru",
        "vidsrc-embed.su",
        "vidsrcme.su",
        "vsrc.su",
        "vsembed.ru",
        "vsembed.su",
        "vidsrcme.ru",
        "cloudnestra.com",
        "cloudorchestranova.com",
        "2embed.cc",
        "streamsrcs.2embed.cc",
        "embed.smashystream.com",
        "smashystream.com",
        "autoembed.cc",
        "multiembed.mov",
        "streamtape.com",
        "streamlare.com",
        "doodstream.com",
        "mixdrop.co",
        "mixdrop.to",
        "vidplay.site",
        "filemoon.sx",
        "upstream.to",
        "streamwish.to",
        "voe.sx",
        "mp4upload.com",
      ];
      const hostMatches = (host, rule) =>
        host === rule || host.endsWith("." + rule) || host.includes(rule);
      const isTrustedPlaybackUrl = (href) => {
        try {
          const u = new URL(href, window.location.href);
          const host = u.hostname.toLowerCase();
          return (
            host === window.location.hostname.toLowerCase() ||
            trustedPlaybackHosts.some((rule) => hostMatches(host, rule))
          );
        } catch (_) {
          return true;
        }
      };

      // Intercept and trap aggressive mouse clicks trying to load redirects,
      // without blocking legitimate nested stream hosts (2Embed/VidSrc hand off
      // to domains such as streamsrcs.2embed.cc and cloudorchestranova.com).
      document.addEventListener(
        "click",
        (e) => {
          let target = e.target;
          while (target && target !== document) {
            if (
              target.tagName === "A" &&
              (target.target === "_blank" ||
                target.getAttribute("href")?.startsWith("http"))
            ) {
              const href = target.getAttribute("href");
              if (href && !isTrustedPlaybackUrl(href)) {
                e.preventDefault();
                e.stopPropagation();
                console.log(
                  "[Omniverse Shield] Blocked click-hijack redirection to: " +
                    href,
                );
                return false;
              }
            }
            target = target.parentNode;
          }
        },
        true,
      );

      // Disable window visibility/focus manipulation by ad frames
      Object.defineProperty(document, "visibilityState", {
        get: () => "visible",
        configurable: true,
      });
      Object.defineProperty(document, "hidden", {
        get: () => false,
        configurable: true,
      });

      console.log("[Omniverse Shield] Defensive Webview Shield initialized.");
    };

    // Inject shield as early as possible
    const container = document.documentElement || document.head;
    if (container) {
      const script = document.createElement("script");
      script.textContent = `(${shieldScript.toString()})();`;
      container.insertBefore(script, container.firstChild);
    }
  } catch (err) {
    console.error("[Omniverse Shield] Injection error: ", err);
  }
}
