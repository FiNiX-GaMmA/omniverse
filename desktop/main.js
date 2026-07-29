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
const {
  ElectronBlocker,
  NetworkFilter,
} = require("@ghostery/adblocker-electron");
const fetch = require("cross-fetch");
const path = require("path");
const fs = require("fs");
const os = require("os");
const { once } = require("events");
const {
  assertTrustedMacUpdateUrl,
  findLocalAppleSigningIdentity,
  launchMacUpdateHelper,
  prepareMacUpdate,
} = require("./macUpdater");
const { BLOCK_KINDS, createAdShieldTelemetry } = require("./adShieldStats");
const {
  assertHttpUrl,
  assertSafeExternalUrl,
  assertTrustedDesktopUpdateUrl,
} = require("./securityPolicy");

// RAM / Performance optimization switches
app.commandLine.appendSwitch(
  "js-flags",
  "--max-old-space-size=256 --expose-gc",
);
app.commandLine.appendSwitch(
  "disable-features",
  "HardwareMediaKeyHandling,MediaSessionService,UseSandboxedXdgPortal",
);
app.commandLine.appendSwitch("disk-cache-size", String(100 * 1024 * 1024)); // 100MB cache limit
app.commandLine.appendSwitch("renderer-process-limit", "3");

// [DEBUG] Toggle verbose player-webview diagnostics to stdout.
const DEBUG_PLAYER = true;

// Global handles
let mainWindow = null;
let pipWindow = null;
let mainBlocker = null;
const blockerAttachedSessions = new WeakSet();
let blockerEventsBound = false;

function publishAdShieldStats(snapshot) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("adshield-stats", snapshot);
  }
}

const adShieldTelemetry = createAdShieldTelemetry({
  onChange: publishAdShieldStats,
});

function recordAdShieldBlock(kind) {
  return adShieldTelemetry.record(kind);
}


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

function bindBlockerEventsOnce() {
  if (!mainBlocker || blockerEventsBound) return;
  mainBlocker.on("request-blocked", (request) => {
    recordAdShieldBlock(BLOCK_KINDS.NETWORK);
    if (DEBUG_PLAYER && request && request.url) {
      console.log("[player-debug][adblock-blocked]", request.url);
    }
  });
  blockerEventsBound = true;
}

function attachBlockerToSession(sess, contextLabel = "session") {
  if (!mainBlocker || !sess || blockerAttachedSessions.has(sess)) return;
  try {
    mainBlocker.enableBlockingInSession(sess);
    blockerAttachedSessions.add(sess);
    bindBlockerEventsOnce();
  } catch (err) {
    console.warn(
      `[Omniverse] Ad-blocker could not attach to ${contextLabel}; continuing without it:`,
      err && err.message ? err.message : err,
    );
  }
}

// Reusable session setup for custom partitions (e.g. video player webview)
async function setupPlaybackSession(playSession) {
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

  // Keep in-player blocking active for all webview-based sources.
  attachBlockerToSession(playSession, "player session");

  // Inject a script into the webview to proactively disable standard redirects and alert-hijacks
  playSession.setPreloads([path.join(__dirname, "preload.js")]);
}

async function createWindow() {
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
      sandbox: true,
      webviewTag: true, // Required for secure embed containers
      backgroundThrottling: true,
      spellcheck: false,
    },
  });

  // Setup the default app session
  const defaultSession = session.defaultSession;

  // Attach blocker to default session as well, so iframe-based player embeds
  // (e.g. VidCore path) still get popup/ad request filtering.
  attachBlockerToSession(defaultSession, "default session");



  // Block popup/new-window attempts from the main frame too (iframe path).
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    recordAdShieldBlock(BLOCK_KINDS.POPUP);
    if (DEBUG_PLAYER) {
      console.log("[player-debug][popup-blocked][main-frame]", url);
    }
    return { action: "deny" };
  });

  // Prevent top-level navigation hijacks away from our app shell.
  mainWindow.webContents.on("will-navigate", (event, url) => {
    // Single-page Electron app shell should never navigate the main BrowserWindow top-level frame.
    event.preventDefault();
    recordAdShieldBlock(BLOCK_KINDS.NAVIGATION);
    if (DEBUG_PLAYER) {
      console.log("[player-debug][nav-blocked][main-frame]", url);
    }
  });

  // Clamp guest preferences before Electron creates an untrusted playback webview.
  mainWindow.webContents.on(
    "will-attach-webview",
    (event, webPreferences, params) => {
      try {
        assertHttpUrl(params.src, "playback webview");
      } catch (_) {
        event.preventDefault();
        return;
      }
      delete webPreferences.preload;
      webPreferences.nodeIntegration = false;
      webPreferences.contextIsolation = true;
      webPreferences.sandbox = true;
    },
  );

  // Configure custom webview permissions and block window redirection popup actions
  mainWindow.webContents.on("did-attach-webview", async (_, wc) => {
    const webviewSession = wc.session;
    await setupPlaybackSession(webviewSession);

    // Completely deny permission to open popup windows / new tabs
    wc.setWindowOpenHandler(({ url }) => {
      recordAdShieldBlock(BLOCK_KINDS.POPUP);
      if (DEBUG_PLAYER) {
        console.log("[player-debug][popup-blocked][webview]", url);
      }
      return { action: "deny" };
    });

    wc.on("enter-html-full-screen", () => {
      mainWindow.webContents.send("webview-fullscreen", true);
    });
    wc.on("leave-html-full-screen", () => {
      mainWindow.webContents.send("webview-fullscreen", false);
    });

    // Surface hard load failures (dead/unreachable source hosts) so the renderer
    // can auto-fall back to the next server instead of showing a black screen.
    wc.on(
      "did-fail-load",
      (event, errorCode, errorDesc, validatedURL, isMainFrame) => {
        // -3 = ERR_ABORTED, fires normally when we swap the src / navigate away.
        if (DEBUG_PLAYER)
          console.log(
            `[player-debug] did-fail-load code=${errorCode} main=${isMainFrame} desc="${errorDesc}" url=${validatedURL}`,
          );
        if (!isMainFrame || errorCode === -3) return;
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("webview-load-failed", {
            errorCode,
            errorDesc,
            url: validatedURL,
          });
        }
      },
    );

    // [DEBUG] player webview load lifecycle — remove once playback is confirmed.
    if (DEBUG_PLAYER) {
      wc.on("did-start-loading", () =>
        console.log("[player-debug] start-loading", wc.getURL()),
      );
      wc.on("dom-ready", () =>
        console.log("[player-debug] dom-ready", wc.getURL()),
      );
      wc.on("did-finish-load", () =>
        console.log("[player-debug] finish-load", wc.getURL()),
      );
      wc.on("did-navigate", (_e, url) =>
        console.log("[player-debug] navigate", url),
      );
      wc.on("console-message", (_e, level, message) =>
        console.log("[player-debug][webview-console]", message),
      );
    }
  });

  mainWindow.loadFile(path.join(__dirname, "index.html"));

  if (process.env.DEBUG === "true" || process.argv.includes("--omni-debug")) {
    mainWindow.webContents.openDevTools();
  }

  mainWindow.on("closed", () => {
    mainWindow = null;
    if (process.platform !== "darwin") app.quit();
  });
}

// IPC Handlers
ipcMain.handle("get-platform", () => process.platform);
ipcMain.handle("get-arch", () => process.arch);

// Clear the HTTP cache for the app + player sessions so a fresh pull re-fetches
// catalogue data and posters. Leaves cookies/localStorage (logins) intact.
ipcMain.handle("clear-cache", async () => {
  try {
    await session.defaultSession.clearCache();
    try {
      await session.fromPartition("persist:player").clearCache();
    } catch (_) {}
    return true;
  } catch (e) {
    return false;
  }
});

// The installed build's version (from package.json, stamped at release time).
// The updater compares this against the latest GitHub release.
ipcMain.handle("get-app-version", () => app.getVersion());

ipcMain.handle("download-update-file", async (event, url) => {
  let downloadDir = null;
  let preparedUpdate = null;
  try {
    const parsed = assertTrustedDesktopUpdateUrl(url, process.platform);
    if (process.platform === "darwin") assertTrustedMacUpdateUrl(url);
    const signingIdentity =
      process.platform === "darwin"
        ? await findLocalAppleSigningIdentity()
        : null;
    downloadDir = fs.mkdtempSync(
      path.join(os.tmpdir(), "omniverse-download-"),
    );
    const rawName = path.basename(parsed.pathname || "") || "omniverse-update";
    const fileName = path.basename(decodeURIComponent(rawName));
    const downloadPath = path.join(downloadDir, fileName);

    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const body = response.body;
    if (!body) throw new Error("Empty update response body");

    const contentLength =
      parseInt(response.headers.get("content-length"), 10) || 0;
    const fileStream = fs.createWriteStream(downloadPath);

    let downloadedBytes = 0;
    const sendProgress = () => {
      if (contentLength <= 0) return;
      const pct = Math.max(
        0,
        Math.min(100, Math.round((downloadedBytes / contentLength) * 100)),
      );
      try {
        event.sender.send(
          "update-progress",
          process.platform === "darwin" ? Math.round(pct * 0.75) : pct,
        );
      } catch (_) {}
    };

    const writeChunk = async (chunk) => {
      const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      downloadedBytes += buf.length;
      if (!fileStream.write(buf)) {
        await once(fileStream, "drain");
      }
      sendProgress();
    };

    try {
      if (typeof body.getReader === "function") {
        const reader = body.getReader();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (value) await writeChunk(value);
        }
      } else if (typeof body[Symbol.asyncIterator] === "function") {
        for await (const chunk of body) {
          if (chunk) await writeChunk(chunk);
        }
      } else {
        throw new Error("Unsupported download stream type");
      }

      await new Promise((resolve, reject) => {
        fileStream.once("error", reject);
        fileStream.end(resolve);
      });
    } catch (streamErr) {
      try {
        fileStream.destroy();
      } catch (_) {}
      try {
        fs.unlinkSync(downloadPath);
      } catch (_) {}
      throw streamErr;
    }

    if (process.platform === "darwin") {
      preparedUpdate = await prepareMacUpdate({
        dmgPath: downloadPath,
        currentExecutable: process.execPath,
        currentVersion: app.getVersion(),
        signingIdentity,
        onProgress: (pct) => {
          try {
            event.sender.send("update-progress", pct);
          } catch (_) {}
        },
      });
      fs.rmSync(downloadDir, { recursive: true, force: true });
      downloadDir = null;
      await launchMacUpdateHelper(preparedUpdate, process.pid);
      try {
        event.sender.send("update-progress", 100);
      } catch (_) {}
      setTimeout(() => app.quit(), 250);
      return {
        ok: true,
        mode: "in-app",
        version: preparedUpdate.candidateVersion,
        identity: preparedUpdate.identity.name,
      };
    }

    try {
      event.sender.send("update-progress", 100);
    } catch (_) {}
    const launchErr = await shell.openPath(downloadPath);
    if (launchErr) throw new Error(launchErr);

    app.quit();
    return { ok: true, path: downloadPath };
  } catch (err) {
    if (process.platform === "darwin" && downloadDir) {
      try {
        fs.rmSync(downloadDir, { recursive: true, force: true });
      } catch (_) {}
    }
    if (process.platform === "darwin" && preparedUpdate) {
      try {
        fs.rmSync(preparedUpdate.workDir, { recursive: true, force: true });
      } catch (_) {}
    }
    return { ok: false, error: err.message };
  }
});

ipcMain.handle(
  "iptv-fetch",
  async (_, { url, method = "GET", headers = {}, body = null }) => {
    try {
      assertHttpUrl(url, "IPTV request");
      const mergedHeaders = {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        ...headers,
      };



      const fetchOptions = {
        method: method.toUpperCase(),
        headers: mergedHeaders,
      };
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

ipcMain.handle("get-adshield-stats", () => adShieldTelemetry.snapshot());

ipcMain.handle("open-external", (_, url) => {
  const trustedUrl = assertSafeExternalUrl(url);
  return shell.openExternal(trustedUrl.toString());
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
ipcMain.handle("open-pip-window", async (_, { url, title }) => {
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

  await setupPlaybackSession(session.fromPartition("persist:pip"));
  pipWindow.loadURL(url);

  pipWindow.webContents.setWindowOpenHandler(() => {
    recordAdShieldBlock(BLOCK_KINDS.POPUP);
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

  app.whenReady().then(async () => {
    mainBlocker = await ElectronBlocker.fromPrebuiltAdsAndTracking(fetch);

    // Whitelist critical source domains to prevent the adblocker from breaking streams
    const whitelistedDomains = [
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
      "multiembed.mov",
      "autoembed.cc",
      "2embed.cc",
      "streamsrcs.2embed.cc",
      "embed.smashystream.com",
      "smashystream.com",
      "pixeldrain.com",
      "api.themoviedb.org",
      "api.trakt.tv",
    ];
    const exceptions = whitelistedDomains
      .map((d) =>
        NetworkFilter.parse(
          `@@||${d}^$important,document,subdocument,script,xmlhttprequest,media,stylesheet,image,font`,
        ),
      )
      .filter(Boolean);
    mainBlocker.update({ newNetworkFilters: exceptions });

    await createWindow();
  });

  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });

  app.on("activate", async () => {
    if (mainWindow === null) await createWindow();
  });
}
