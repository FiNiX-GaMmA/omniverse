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
  window.location.protocol === "chrome-extension:";

if (isMainApp) {
  // Expose secure API to the main application
  contextBridge.exposeInMainWorld("electron", {
    getPlatform: () => ipcRenderer.invoke("get-platform"),
    minimize: () => ipcRenderer.invoke("window-minimize"),
    maximize: () => ipcRenderer.invoke("window-maximize"),
    close: () => ipcRenderer.invoke("window-close"),
    openExternal: (url) => ipcRenderer.invoke("open-external", url),
    openPipWindow: (url, title) =>
      ipcRenderer.invoke("open-pip-window", { url, title }),
    closePipWindow: () => ipcRenderer.invoke("close-pip-window"),
    iptvFetch: (url) => ipcRenderer.invoke("iptv-fetch", url),
    downloadUpdate: (url) => ipcRenderer.invoke("download-update-file", url),
    onUpdateProgress: (cb) => {
      const handler = (_, pct) => cb(pct);
      ipcRenderer.on("update-progress", handler);
      return () => ipcRenderer.removeListener("update-progress", handler);
    },
    getAdblockStats: () => ipcRenderer.invoke("get-adblock-stats"),
    showNotification: (title, body) =>
      ipcRenderer.invoke("show-notification", { title, body }),
    onAdBlocked: (cb) => {
      const handler = (_, count) => cb(count);
      ipcRenderer.on("ad-blocked", handler);
      return () => ipcRenderer.removeListener("ad-blocked", handler);
    },
    onWebviewFullscreen: (cb) => {
      const handler = (_, state) => cb(state);
      ipcRenderer.on("webview-fullscreen", handler);
      return () => ipcRenderer.removeListener("webview-fullscreen", handler);
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

      // Intercept and trap aggressive mouse clicks trying to load redirects
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
              // If it's a redirect to an untrusted domain, block it
              if (
                href &&
                !href.includes(window.location.hostname) &&
                !href.includes("vidsrc") &&
                !href.includes("vidsrc.to")
              ) {
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
