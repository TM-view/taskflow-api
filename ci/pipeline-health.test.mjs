import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateBuildHealth } from './pipeline-health-lib.mjs';

function metric(number, ordinal) {
  return { metric: { number: String(number) }, value: ['1790770315.061', String(ordinal)] };
}

test('uses the 20 latest completed builds and excludes the current build', () => {
  const series = Array.from({ length: 25 }, (_, i) => metric(i + 1, 0));
  const result = evaluateBuildHealth(series, { currentBuild: 26 });
  assert.equal(result.buildCount, 20);
  assert.equal(result.latestBuild, 25);
  assert.equal(result.oldestBuild, 6);
  assert.equal(result.successRate, 1);
});

test('blocks when fewer than 20 completed builds are available', () => {
  const result = evaluateBuildHealth(Array.from({ length: 19 }, (_, i) => metric(i + 1, 0)));
  assert.equal(result.blocked, true);
  assert.match(result.reason, /needs 20/i);
});

test('allows exactly a 90 percent success rate', () => {
  const result = evaluateBuildHealth([
    ...Array.from({ length: 18 }, (_, i) => metric(i + 1, 0)),
    metric(19, 1),
    metric(20, 2),
  ]);
  assert.equal(result.successCount, 18);
  assert.equal(result.successRate, 0.9);
  assert.equal(result.blocked, false);
});

test('blocks a rate below 90 percent and counts unstable as non-success', () => {
  const result = evaluateBuildHealth([
    ...Array.from({ length: 17 }, (_, i) => metric(i + 1, 0)),
    metric(18, 1),
    metric(19, 2),
    metric(20, 4),
  ]);
  assert.equal(result.successCount, 17);
  assert.equal(result.successRate, 0.85);
  assert.equal(result.blocked, true);
});
