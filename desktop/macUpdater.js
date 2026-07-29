const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile, spawn } = require("child_process");
const { promisify } = require("util");
const { assertTrustedDesktopUpdateUrl } = require("./securityPolicy");

const execFileAsync = promisify(execFile);
const EXPECTED_BUNDLE_ID = "com.finix.omniverse.desktop";

function assertTrustedMacUpdateUrl(rawUrl) {
  return assertTrustedDesktopUpdateUrl(rawUrl, "darwin");
}

function compareVersions(left, right) {
  const a = String(left || "0")
    .replace(/^v/i, "")
    .split(".")
    .map((value) => Number.parseInt(value, 10) || 0);
  const b = String(right || "0")
    .replace(/^v/i, "")
    .split(".")
    .map((value) => Number.parseInt(value, 10) || 0);
  const size = Math.max(a.length, b.length);
  for (let index = 0; index < size; index += 1) {
    if ((a[index] || 0) > (b[index] || 0)) return 1;
    if ((a[index] || 0) < (b[index] || 0)) return -1;
  }
  return 0;
}

function parseSigningIdentities(output) {
  const identities = [];
  for (const line of String(output || "").split("\n")) {
    const match = line.match(/^\s*\d+\)\s+([A-F0-9]{40})\s+"([^"]+)"/i);
    if (match) identities.push({ hash: match[1], name: match[2] });
  }
  return identities;
}

function selectLocalAppleSigningIdentity(identities) {
  return (
    identities.find((identity) =>
      identity.name.startsWith("Apple Development:"),
    ) ||
    identities.find((identity) =>
      identity.name.startsWith("Developer ID Application:"),
    ) ||
    null
  );
}

async function findLocalAppleSigningIdentity() {
  const { stdout } = await execFileAsync("/usr/bin/security", [
    "find-identity",
    "-v",
    "-p",
    "codesigning",
  ]);
  const identities = parseSigningIdentities(stdout);
  const preferred = selectLocalAppleSigningIdentity(identities);
  if (!preferred) {
    throw new Error(
      "No Developer ID Application or Apple Development signing identity was found in the login keychain",
    );
  }
  return preferred;
}

function installedAppPathFromExecutable(executablePath) {
  const appPath = path.resolve(executablePath, "..", "..", "..");
  if (path.extname(appPath).toLowerCase() !== ".app") {
    throw new Error("The updater can only replace a packaged macOS .app bundle");
  }
  return appPath;
}

async function readPlistValue(appPath, key) {
  const plistPath = path.join(appPath, "Contents", "Info.plist");
  const { stdout } = await execFileAsync("/usr/libexec/PlistBuddy", [
    "-c",
    `Print :${key}`,
    plistPath,
  ]);
  return stdout.trim();
}

async function copyApp(source, destination) {
  await execFileAsync("/usr/bin/ditto", [source, destination]);
}

async function verifyAppSignature(appPath) {
  await execFileAsync("/usr/bin/codesign", [
    "--verify",
    "--deep",
    "--strict",
    "--verbose=2",
    appPath,
  ]);
}

async function signAppWithLocalIdentity(appPath, identity) {
  if (!identity || !identity.hash) {
    throw new Error("A valid local Apple signing identity is required");
  }
  await execFileAsync("/usr/bin/codesign", [
    "--force",
    "--deep",
    "--options",
    "runtime",
    "--preserve-metadata=identifier,entitlements,flags,runtime",
    "--timestamp=none",
    "--sign",
    identity.hash,
    appPath,
  ]);
}

async function clearQuarantine(appPath) {
  try {
    await execFileAsync("/usr/bin/xattr", [
      "-dr",
      "com.apple.quarantine",
      appPath,
    ]);
  } catch (error) {
    const message = `${error.stderr || ""}${error.message || ""}`;
    if (!message.includes("No such xattr")) throw error;
  }
}

async function prepareMacUpdate({
  dmgPath,
  currentExecutable,
  currentVersion,
  signingIdentity = null,
  onProgress = () => {},
}) {
  const targetApp = installedAppPathFromExecutable(currentExecutable);
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "omniverse-update-"));
  const mountPoint = path.join(workDir, "mount");
  const stagedApp = path.join(workDir, "Omniverse.app");
  const backupApp = path.join(workDir, "Omniverse.backup.app");
  fs.mkdirSync(mountPoint);
  let attached = false;
  let preparedSuccessfully = false;

  try {
    onProgress(78);
    await execFileAsync("/usr/bin/hdiutil", [
      "attach",
      "-nobrowse",
      "-readonly",
      "-mountpoint",
      mountPoint,
      dmgPath,
    ]);
    attached = true;

    const candidates = fs
      .readdirSync(mountPoint, { withFileTypes: true })
      .filter(
        (entry) => entry.isDirectory() && entry.name.toLowerCase().endsWith(".app"),
      )
      .map((entry) => path.join(mountPoint, entry.name));
    if (candidates.length !== 1) {
      throw new Error("The update image must contain exactly one .app bundle");
    }

    const candidateApp = candidates[0];
    const installedBundleId = await readPlistValue(
      targetApp,
      "CFBundleIdentifier",
    );
    if (installedBundleId !== EXPECTED_BUNDLE_ID) {
      throw new Error(`Unexpected installed bundle identifier: ${installedBundleId}`);
    }
    const bundleId = await readPlistValue(candidateApp, "CFBundleIdentifier");
    if (bundleId !== EXPECTED_BUNDLE_ID) {
      throw new Error(`Unexpected update bundle identifier: ${bundleId}`);
    }

    const candidateVersion = await readPlistValue(
      candidateApp,
      "CFBundleShortVersionString",
    );
    if (compareVersions(candidateVersion, currentVersion) <= 0) {
      throw new Error(
        `Update version ${candidateVersion} is not newer than ${currentVersion}`,
      );
    }

    onProgress(82);
    await copyApp(candidateApp, stagedApp);
    await copyApp(targetApp, backupApp);

    const identity = signingIdentity || (await findLocalAppleSigningIdentity());
    onProgress(88);
    await signAppWithLocalIdentity(stagedApp, identity);
    await verifyAppSignature(stagedApp);

    onProgress(94);
    await clearQuarantine(stagedApp);
    await verifyAppSignature(stagedApp);

    preparedSuccessfully = true;
    return {
      workDir,
      stagedApp,
      backupApp,
      targetApp,
      candidateVersion,
      identity,
    };
  } finally {
    if (attached) {
      try {
        await execFileAsync("/usr/bin/hdiutil", ["detach", mountPoint]);
      } catch (_) {}
    }
    if (!preparedSuccessfully) {
      fs.rmSync(workDir, { recursive: true, force: true });
    }
  }
}

function buildMacUpdateHelperScript() {
  return String.raw`
set -u
cleanup() {
  /bin/rm -rf "$OMNI_WORK_DIR"
}
restore_backup() {
  /bin/echo "Restoring previous Omniverse installation"
  /bin/rm -rf "$OMNI_TARGET_APP/Contents" || return 1
  /usr/bin/ditto "$OMNI_BACKUP_APP/Contents" "$OMNI_TARGET_APP/Contents" || return 1
  /usr/bin/xattr -dr com.apple.quarantine "$OMNI_TARGET_APP" 2>/dev/null || true
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$OMNI_TARGET_APP"
}

/bin/echo "Waiting for Omniverse process $OMNI_PARENT_PID to exit"
while /bin/kill -0 "$OMNI_PARENT_PID" 2>/dev/null; do /bin/sleep 0.25; done

/bin/echo "Installing signed update $OMNI_CANDIDATE_VERSION"
/bin/rm -rf "$OMNI_TARGET_APP/Contents" || {
  /bin/echo "Could not remove the existing application contents"
  cleanup
  exit 1
}

if ! /usr/bin/ditto "$OMNI_STAGED_APP/Contents" "$OMNI_TARGET_APP/Contents"; then
  /bin/echo "Update copy failed"
  restore_backup || exit 2
  /usr/bin/open -n "$OMNI_TARGET_APP" || true
  cleanup
  exit 1
fi

/usr/bin/xattr -dr com.apple.quarantine "$OMNI_TARGET_APP" 2>/dev/null || true
if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$OMNI_TARGET_APP" || \
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OMNI_TARGET_APP/Contents/Info.plist" 2>/dev/null)" != "$OMNI_BUNDLE_ID" ] || \
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OMNI_TARGET_APP/Contents/Info.plist" 2>/dev/null)" != "$OMNI_CANDIDATE_VERSION" ]; then
  /bin/echo "Update validation failed"
  restore_backup || {
    /bin/echo "Rollback failed; backup retained at $OMNI_BACKUP_APP"
    exit 2
  }
  /usr/bin/open -n "$OMNI_TARGET_APP" || true
  cleanup
  exit 1
fi

/bin/echo "Signature and bundle metadata validated; launching Omniverse"
if ! /usr/bin/open -n "$OMNI_TARGET_APP"; then
  /bin/echo "Updated application did not launch; rolling back"
  restore_backup || exit 2
  /usr/bin/open -n "$OMNI_TARGET_APP" || true
  cleanup
  exit 1
fi

/bin/echo "Update completed successfully"
cleanup
`;
}

function launchMacUpdateHelper(prepared, parentPid) {
  const logDir = path.join(os.homedir(), "Library", "Logs");
  fs.mkdirSync(logDir, { recursive: true });
  const logFd = fs.openSync(path.join(logDir, "OmniverseUpdater.log"), "a");
  const script = buildMacUpdateHelperScript();
  const helper = spawn("/bin/sh", ["-c", script], {
    detached: true,
    stdio: ["ignore", logFd, logFd],
    env: {
      PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
      OMNI_PARENT_PID: String(parentPid),
      OMNI_STAGED_APP: prepared.stagedApp,
      OMNI_BACKUP_APP: prepared.backupApp,
      OMNI_TARGET_APP: prepared.targetApp,
      OMNI_WORK_DIR: prepared.workDir,
      OMNI_BUNDLE_ID: EXPECTED_BUNDLE_ID,
      OMNI_CANDIDATE_VERSION: prepared.candidateVersion,
    },
  });
  return new Promise((resolve, reject) => {
    let settled = false;
    const closeLog = () => {
      try {
        fs.closeSync(logFd);
      } catch (_) {}
    };
    helper.once("spawn", () => {
      settled = true;
      helper.unref();
      closeLog();
      resolve();
    });
    helper.once("error", (error) => {
      if (settled) return;
      settled = true;
      closeLog();
      reject(error);
    });
  });
}

module.exports = {
  assertTrustedMacUpdateUrl,
  buildMacUpdateHelperScript,
  compareVersions,
  findLocalAppleSigningIdentity,
  installedAppPathFromExecutable,
  launchMacUpdateHelper,
  parseSigningIdentities,
  prepareMacUpdate,
  selectLocalAppleSigningIdentity,
  signAppWithLocalIdentity,
};
