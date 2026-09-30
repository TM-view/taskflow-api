export function evaluateBuildHealth(series, { currentBuild = 0, limit = 20, minimumRate = 0.9 } = {}) {
  const builds = series
    .map(({ metric, value }) => ({
      number: Number(metric?.number),
      resultOrdinal: Number(value?.[1]),
    }))
    .filter(({ number, resultOrdinal }) => Number.isInteger(number) && Number.isFinite(resultOrdinal))
    .filter(({ number }) => !currentBuild || number < Number(currentBuild))
    .sort((a, b) => b.number - a.number)
    .slice(0, limit);

  if (builds.length < limit) {
    return {
      buildCount: builds.length,
      latestBuild: builds[0]?.number ?? null,
      oldestBuild: builds.at(-1)?.number ?? null,
      successCount: builds.filter(({ resultOrdinal }) => resultOrdinal === 0).length,
      successRate: builds.length ? builds.filter(({ resultOrdinal }) => resultOrdinal === 0).length / builds.length : 0,
      blocked: true,
      reason: `Health gate needs ${limit} completed builds; Prometheus has ${builds.length}.`,
    };
  }

  const successCount = builds.filter(({ resultOrdinal }) => resultOrdinal === 0).length;
  const successRate = successCount / builds.length;
  return {
    buildCount: builds.length,
    latestBuild: builds[0].number,
    oldestBuild: builds.at(-1).number,
    successCount,
    successRate,
    blocked: successRate < minimumRate,
    reason: successRate < minimumRate
      ? `Health gate blocked production deployment: rolling success rate ${(successRate * 100).toFixed(1)}% is below ${minimumRate * 100}%.`
      : null,
  };
}
