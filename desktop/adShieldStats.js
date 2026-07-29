"use strict";

const BLOCK_KINDS = Object.freeze({
  NETWORK: "network",
  POPUP: "popup",
  NAVIGATION: "navigation",
});

const COUNTER_BY_KIND = Object.freeze({
  [BLOCK_KINDS.NETWORK]: "networkBlocked",
  [BLOCK_KINDS.POPUP]: "popupsBlocked",
  [BLOCK_KINDS.NAVIGATION]: "navigationsBlocked",
});

function createAdShieldTelemetry({ now = Date.now, onChange = () => {} } = {}) {
  const startedAt = now();
  const stats = {
    totalBlocked: 0,
    networkBlocked: 0,
    popupsBlocked: 0,
    navigationsBlocked: 0,
    sessionStartedAt: startedAt,
    lastBlockedAt: null,
    lastKind: null,
  };

  const snapshot = () => Object.freeze({ ...stats });

  return Object.freeze({
    record(kind) {
      const counter = COUNTER_BY_KIND[kind];
      if (!counter) throw new TypeError(`Unknown AdShield block kind: ${kind}`);

      stats.totalBlocked += 1;
      stats[counter] += 1;
      stats.lastBlockedAt = now();
      stats.lastKind = kind;

      const next = snapshot();
      try {
        onChange(next);
      } catch (_) {
        // Telemetry must never interrupt request or navigation blocking.
      }
      return next;
    },
    snapshot,
  });
}

module.exports = {
  BLOCK_KINDS,
  createAdShieldTelemetry,
};
