// ==============================================================================
// Omniverse Desktop — Main Electron Process
// ==============================================================================
// Orchestrates the desktop lifecycle, custom titlebars, Picture-in-Picture mode,
// and a powerful, low-overhead ad/tracker network filter for clean streaming.
// ==============================================================================

const {
  app,
  BrowserWindow,
  ipcMain,
  session,
  shell,
  Notification,
} = require("electron");
const path = require("path");
const fs = require("fs");
const os = require("os");

// RAM / Performance optimization switches
app.commandLine.appendSwitch(
  "js-flags",
  "--max-old-space-size=256 --expose-gc",
);
app.commandLine.appendSwitch(
  "disable-features",
  "HardwareMediaKeyHandling,MediaSessionService,UseSandboxedXdgPortal",
);
app.commandLine.appendSwitch("enable-features", "NetworkServiceInProcess2");
app.commandLine.appendSwitch("disk-cache-size", String(100 * 1024 * 1024)); // 100MB cache limit
app.commandLine.appendSwitch("renderer-process-limit", "3");

// Global handles
let mainWindow = null;
let pipWindow = null;
let adBlockStats = { adsBlocked: 0 };
// Hosts of resolved anime direct streams that need a Referer. Scoped so Live TV
// and other media are untouched. Populated by the renderer before playback.
const animeRefererHosts = new Set();

// Extended list of ad network, tracker, popunder, and anti-devtool script domains
const BLOCKED_KEYWORDS = [
  "google-analytics.com",
  "analytics.google.com",
  "googletagmanager.com",
  "googletagservices.com",
  "doubleclick.net",
  "adservice.google.com",
  "pagead2.googlesyndication.com",
  "stats.g.doubleclick.net",
  "adx1.com",
  "intelligenceadx.com",
  "adsco.re",
  "mc.yandex.ru",
  "mc.yandex.com",
  "rtmark.net",
  "acscdn.com",
  "protrafficinspector.com",
  "histats.com",
  "cloudflareinsights.com",
  "kettledroopingcontinuation.com",
  "wayfarerorthodox.com",
  "woxaglasuy.net",
  "adeptspiritual.com",
  "calculating-laugh.com",
  "onclickads",
  "adsterra",
  "exoclick",
  "popads",
  "popcash",
  "propellerads",
  "juicyads",
  "disable-devtool",
];

// Reusable session setup for custom partitions (e.g. video player webview)
function setupPlaybackSession(playSession) {
  const UA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
  playSession.setUserAgent(UA);

  // Strip Content-Security-Policy and X-Frame-Options to allow embedding of protected stream URLs
  playSession.webRequest.onHeadersReceived(
    { urls: ["*://*/*"] },
    (details, callback) => {
      const headers = { ...details.responseHeaders };
      for (const key of Object.keys(headers)) {
        const lower = key.toLowerCase();
        if (
          lower === "x-frame-options" ||
          lower === "content-security-policy" ||
          lower === "frame-options"
        ) {
          delete headers[key];
        }
      }
      callback({ responseHeaders: headers });
    },
  );

  // Block ad networks, tracking scripts, and pop-up loaders
  playSession.webRequest.onBeforeRequest(
    { urls: BLOCKED_HOSTS },
    (details, callback) => {
      adBlockStats.adsBlocked++;
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send("ad-blocked", adBlockStats.adsBlocked);
      }
      callback({ cancel: true });
    },
  );

  // Inject a script into the webview to proactively disable standard redirects and alert-hijacks
  playSession.setPreloads([path.join(__dirname, "preload.js")]);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1380,
    height: 850,
    minWidth: 1024,
    minHeight: 700,
    backgroundColor: "#0d0e12",
    title: "Omniverse",
    titleBarStyle: process.platform === "darwin" ? "hiddenInset" : "hidden",
    frame: process.platform === "darwin", // Frameless on Windows and Linux for premium native layout
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true, // Required for secure embed containers
      backgroundThrottling: true,
      spellcheck: false,
    },
  });

  // Setup the default app session
  const defaultSession = session.defaultSession;

  // Custom headers to optimize cache times for TMDB assets
  defaultSession.webRequest.onHeadersReceived(
    { urls: ["*://image.tmdb.org/*"] },
    (details, callback) => {
      const headers = { ...details.responseHeaders };
      headers["cache-control"] = ["public, max-age=604800, immutable"]; // Cache for 7 days
      delete headers["pragma"];
      delete headers["expires"];
      callback({ responseHeaders: headers });
    },
  );

  // Anime direct streams (AllAnime CDNs) require a Referer. Inject it only for
  // the exact stream host(s) the renderer registers, leaving Live TV/others alone.
  defaultSession.webRequest.onBeforeSendHeaders(
    { urls: ["*://*/*"] },
    (details, callback) => {
      try {
        const host = new URL(details.url).host;
        if (animeRefererHosts.has(host)) {
          details.requestHeaders["Referer"] = "https://allmanga.to";
          details.requestHeaders["Origin"] = "https://allmanga.to";
        }
      } catch (_) {}
      callback({ requestHeaders: details.requestHeaders });
    },
  );

  // Configure custom webview permissions and block window redirection popup actions
  mainWindow.webContents.on("did-attach-webview", (_, wc) => {
    const webviewSession = wc.session;
    setupPlaybackSession(webviewSession);

    // Completely deny permission to open popup windows / new tabs
    wc.setWindowOpenHandler(() => {
      adBlockStats.adsBlocked++;
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send("ad-blocked", adBlockStats.adsBlocked);
      }
      return { action: "deny" };
    });

    wc.on("enter-html-full-screen", () => {
      mainWindow.webContents.send("webview-fullscreen", true);
    });
    wc.on("leave-html-full-screen", () => {
      mainWindow.webContents.send("webview-fullscreen", false);
    });
  });

  mainWindow.loadFile(path.join(__dirname, "index.html"));

  mainWindow.on("closed", () => {
    mainWindow = null;
    if (process.platform !== "darwin") app.quit();
  });
}

// IPC Handlers
ipcMain.handle("get-platform", () => process.platform);
ipcMain.handle("get-arch", () => process.arch);

// The installed build's version (from package.json, stamped at release time).
// The updater compares this against the latest GitHub release.
ipcMain.handle("get-app-version", () => app.getVersion());

ipcMain.handle("download-update-file", async (event, url) => {
  try {
    const tempDir = os.tmpdir();
    const fileName = path.basename(new URL(url).pathname);
    const downloadPath = path.join(tempDir, fileName);

    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const contentLength =
      parseInt(response.headers.get("content-length"), 10) || 0;
    const fileStream = fs.createWriteStream(downloadPath);

    const reader = response.body.getReader();
    let downloadedBytes = 0;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      downloadedBytes += value.length;
      fileStream.write(Buffer.from(value));

      if (contentLength > 0) {
        const pct = Math.round((downloadedBytes / contentLength) * 100);
        event.sender.send("update-progress", pct);
      }
    }

    fileStream.end();

    // Run the installer and quit the app
    setTimeout(() => {
      shell.openPath(downloadPath).then((err) => {
        if (!err) {
          app.quit();
        }
      });
    }, 1000);

    return { ok: true, path: downloadPath };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle(
  "iptv-fetch",
  async (_, { url, method = "GET", headers = {}, body = null }) => {
    try {
      const mergedHeaders = {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        ...headers,
      };

      // Forward the captcha-solved session cookies to AllAnime so a retry after
      // NEED_CAPTCHA is authenticated. Cookies live in the persist:player
      // partition (where the captcha WebView solved them).
      try {
        const host = new URL(url).host;
        if (/(?:^|\.)allanime\.day$|(?:^|\.)allmanga\.to$/.test(host)) {
          const playSession = session.fromPartition("persist:player");
          const cookies = await playSession.cookies.get({ url });
          if (cookies && cookies.length) {
            mergedHeaders["Cookie"] = cookies
              .map((c) => `${c.name}=${c.value}`)
              .join("; ");
          }
        }
      } catch (_) {}

      const fetchOptions = { method: method.toUpperCase(), headers: mergedHeaders };
      if (body) {
        fetchOptions.body =
          typeof body === "string" ? body : JSON.stringify(body);
      }

      // Add a robust 8-second request timeout via AbortController to prevent infinite hangs
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 8000);
      fetchOptions.signal = controller.signal;

      try {
        const response = await fetch(url, fetchOptions);
        const html = await response.text();
        return { ok: response.ok, status: response.status, html };
      } finally {
        clearTimeout(timeoutId);
      }
    } catch (err) {
      return { ok: false, error: err.message };
    }
  },
);

// Renderer registers the resolved anime stream host so the Referer injector
// (default session) targets exactly that host.
ipcMain.handle("register-anime-host", (_, host) => {
  if (host) animeRefererHosts.add(host);
  return true;
});

// After a captcha is solved, cookies are already in the persist:player
// partition; iptv-fetch reads them at request time. This is a trigger/no-op.
ipcMain.handle("sync-player-cookies", () => true);

// Player teardown hook (GC/cache). Safe no-op kept for the renderer's exitPlayer.
ipcMain.handle("player-stopped", () => {
  try {
    if (global.gc) global.gc();
  } catch (_) {}
  return true;
});

ipcMain.handle("get-adblock-stats", () => adBlockStats.adsBlocked);

ipcMain.handle("open-external", (_, url) => {
  shell.openExternal(url);
});

// Windows/Linux Titlebar Operations
ipcMain.handle("window-minimize", () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.handle("window-maximize", () => {
  if (mainWindow) {
    if (mainWindow.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow.maximize();
    }
  }
});

ipcMain.handle("window-close", () => {
  if (mainWindow) mainWindow.close();
});

// Picture-in-Picture (PiP) Window Controller
ipcMain.handle("open-pip-window", (_, { url, title }) => {
  if (pipWindow && !pipWindow.isDestroyed()) {
    pipWindow.loadURL(url);
    pipWindow.focus();
    return { ok: true };
  }

  pipWindow = new BrowserWindow({
    width: 580,
    height: 330,
    minWidth: 320,
    minHeight: 180,
    alwaysOnTop: true,
    backgroundColor: "#000000",
    title: title ? `${title} — Picture-in-Picture` : "Omniverse PiP",
    titleBarStyle: "hidden",
    frame: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      partition: "persist:pip",
      webviewTag: true,
    },
  });

  setupPlaybackSession(session.fromPartition("persist:pip"));
  pipWindow.loadURL(url);

  pipWindow.webContents.setWindowOpenHandler(() => {
    adBlockStats.adsBlocked++;
    return { action: "deny" };
  });

  pipWindow.on("closed", () => {
    pipWindow = null;
  });

  return { ok: true };
});

ipcMain.handle("close-pip-window", () => {
  if (pipWindow && !pipWindow.isDestroyed()) {
    pipWindow.close();
  }
});

// Native Push Notifications
ipcMain.handle("show-notification", (_, { title, body }) => {
  try {
    if (Notification.isSupported()) {
      const notification = new Notification({
        title: title,
        body: body,
        icon: path.join(__dirname, "logo.png"),
      });
      notification.show();
    }
  } catch (err) {
    console.error("Failed to show native notification:", err);
  }
  return { ok: true };
});

// Single-instance lock to prevent double-booting
const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(createWindow);

  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });

  app.on("activate", () => {
    if (mainWindow === null) createWindow();
  });
}
