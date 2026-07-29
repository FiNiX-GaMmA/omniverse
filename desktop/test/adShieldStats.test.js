"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  BLOCK_KINDS,
  createAdShieldTelemetry,
} = require("../adShieldStats");

test("tracks each protection layer and emits immutable snapshots", () => {
  let clock = 1_000;
  const changes = [];
  const telemetry = createAdShieldTelemetry({
    now: () => clock,
    onChange: (snapshot) => changes.push(snapshot),
  });

  clock = 1_100;
  telemetry.record(BLOCK_KINDS.NETWORK);
  clock = 1_200;
  telemetry.record(BLOCK_KINDS.POPUP);
  clock = 1_300;
  const snapshot = telemetry.record(BLOCK_KINDS.NAVIGATION);

  assert.deepEqual(snapshot, {
    totalBlocked: 3,
    networkBlocked: 1,
    popupsBlocked: 1,
    navigationsBlocked: 1,
    sessionStartedAt: 1_000,
    lastBlockedAt: 1_300,
    lastKind: "navigation",
  });
  assert.equal(changes.length, 3);
  assert.equal(Object.isFrozen(snapshot), true);
  assert.throws(() => {
    snapshot.totalBlocked = 99;
  }, TypeError);
  assert.equal(telemetry.snapshot().totalBlocked, 3);
});

test("rejects unknown block kinds without corrupting totals", () => {
  const telemetry = createAdShieldTelemetry();
  assert.throws(() => telemetry.record("other"), /Unknown AdShield block kind/);
  assert.equal(telemetry.snapshot().totalBlocked, 0);
});

test("dashboard callbacks cannot interrupt active protection", () => {
  const telemetry = createAdShieldTelemetry({
    onChange: () => {
      throw new Error("renderer unavailable");
    },
  });
  assert.doesNotThrow(() => telemetry.record(BLOCK_KINDS.POPUP));
  assert.equal(telemetry.snapshot().popupsBlocked, 1);
});
