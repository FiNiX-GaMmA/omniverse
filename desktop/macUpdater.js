const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile, spawn } = require("child_process");
const { promisify } = require("util");
const { assertTrustedDesktopUpdateUrl } = require("./securityPolicy");

const execFileAsync = promisify(execFile);
const EXPECTED_BUNDLE_ID = "com.finix.omniverse.desktop";
const ELECTRON_ENTITLEMENTS = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key>
  <true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
  <key>com.apple.security.cs.allow-dyld-environment-variables</key>
  <true/>
</dict>
</plist>
`;

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

function sortCodeTargetsInsideOut(targets, appPath) {
  const uniqueTargets = [...new Set(targets)];
  const depth = (target) =>
    path.resolve(target).split(path.sep).filter(Boolean).length;

  return uniqueTargets.sort((left, right) => {
    if (left === appPath) return 1;
    if (right === appPath) return -1;
    const depthDifference = depth(right) - depth(left);
    if (depthDifference !== 0) return depthDifference;
    return left.localeCompare(right);
  });
}

async function isMachO(filePath) {
  try {
    const { stdout } = await execFileAsync("/usr/bin/file", ["-b", filePath]);
    return stdout.includes("Mach-O");
  } catch (_) {
    return false;
  }
}

async function collectCodeTargets(appPath) {
  const bundleTargets = [];
  const files = [];

  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const target = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        visit(target);
        if (entry.name.endsWith(".framework") || entry.name.endsWith(".app")) {
          bundleTargets.push(target);
        }
      } else if (entry.isFile()) {
        files.push(target);
      }
    }
  }

  visit(appPath);
  const machOTargets = [];
  for (const file of files) {
    if (await isMachO(file)) machOTargets.push(file);
  }
  return sortCodeTargetsInsideOut(
    [...machOTargets, ...bundleTargets, appPath],
    appPath,
  );
}

async function hasCodeSignature(target) {
  try {
    await execFileAsync("/usr/bin/codesign", ["--display", target]);
    return true;
  } catch (_) {
    return false;
  }
}

async function signingTeamIdentifier(target) {
  const { stderr } = await execFileAsync("/usr/bin/codesign", [
    "--display",
    "--verbose=2",
    target,
  ]);
  return String(stderr || "").match(/^TeamIdentifier=(.+)$/m)?.[1]?.trim() || "";
}

async function verifyNestedTeamIdentifiers(appPath, targets) {
  const expectedTeam = await signingTeamIdentifier(appPath);
  if (!expectedTeam || expectedTeam === "not set") {
    throw new Error("The re-signed application has no Apple Team Identifier");
  }
  const mismatches = [];
  for (const target of targets) {
    const team = await signingTeamIdentifier(target);
    if (team !== expectedTeam) {
      mismatches.push(`${path.relative(appPath, target) || "."}: ${team || "missing"}`);
    }
  }
  if (mismatches.length > 0) {
    throw new Error(
      `Nested code has a different Apple Team Identifier (${mismatches.join(", ")})`,
    );
  }
}

function needsElectronEntitlements(target) {
  return (
    target.endsWith(".app") ||
    target.includes(`${path.sep}Contents${path.sep}MacOS${path.sep}`)
  );
}

async function verifyElectronEntitlements(targets) {
  for (const target of targets.filter(needsElectronEntitlements)) {
    const { stdout, stderr } = await execFileAsync("/usr/bin/codesign", [
      "--display",
      "--entitlements",
      "-",
      target,
    ]);
    const entitlements = `${stdout || ""}${stderr || ""}`;
    if (
      !entitlements.includes("com.apple.security.cs.allow-jit") ||
      !entitlements.includes("com.apple.security.cs.allow-unsigned-executable-memory")
    ) {
      throw new Error(
        `Electron JIT entitlements are missing from ${path.basename(target)}`,
      );
    }
  }
}

async function signAppWithLocalIdentity(appPath, identity) {
  if (!identity || !identity.hash) {
    throw new Error("A valid local Apple signing identity is required");
  }
  const targets = await collectCodeTargets(appPath);
  const entitlementsDir = fs.mkdtempSync(
    path.join(os.tmpdir(), "omniverse-entitlements-"),
  );
  const entitlementsPath = path.join(entitlementsDir, "entitlements.plist");
  fs.writeFileSync(entitlementsPath, ELECTRON_ENTITLEMENTS, { mode: 0o600 });
  try {
    for (const target of targets) {
      const applyEntitlements = needsElectronEntitlements(target);
      const args = ["--force", "--options", "runtime"];
      if (await hasCodeSignature(target)) {
        args.push(
          applyEntitlements
            ? "--preserve-metadata=identifier,flags,runtime"
            : "--preserve-metadata=identifier,entitlements,flags,runtime",
        );
      }
      if (applyEntitlements) {
        args.push("--entitlements", entitlementsPath);
      }
      args.push("--timestamp=none", "--sign", identity.hash, target);
      await execFileAsync("/usr/bin/codesign", args);
    }
  } finally {
    fs.rmSync(entitlementsDir, { recursive: true, force: true });
  }
  await verifyAppSignature(appPath);
  await verifyNestedTeamIdentifiers(appPath, targets);
  await verifyElectronEntitlements(targets);
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
  needsElectronEntitlements,
  parseSigningIdentities,
  prepareMacUpdate,
  selectLocalAppleSigningIdentity,
  signAppWithLocalIdentity,
  sortCodeTargetsInsideOut,
};
