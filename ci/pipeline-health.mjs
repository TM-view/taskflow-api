const baseUrl = process.env.PROMETHEUS_URL;
const job = process.env.PROMETHEUS_JENKINS_JOB || 'taskflow-api';
const currentBuild = Number(process.env.BUILD_NUMBER || 0);

if (!baseUrl) {
  throw new Error('PROMETHEUS_URL is required; refusing production deploy without the health gate.');
}

const selector = `default_jenkins_builds_build_result_ordinal{jenkins_job="${job.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"}`;
const url = new URL('/api/v1/query', baseUrl);
url.searchParams.set('query', selector);

const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
if (!response.ok) throw new Error(`Prometheus returned HTTP ${response.status}`);
const payload = await response.json();
if (payload.status !== 'success' || !Array.isArray(payload.data?.result)) {
  throw new Error('Prometheus returned an invalid build-metrics response.');
}

const builds = payload.data.result
  .map(({ metric, value }) => ({
    number: Number(metric.number),
    resultOrdinal: Number(value?.[1]),
  }))
  .filter(({ number, resultOrdinal }) => Number.isInteger(number) && Number.isFinite(resultOrdinal))
  .filter(({ number }) => !currentBuild || number < currentBuild)
  .sort((a, b) => b.number - a.number)
  .slice(0, 20);

if (builds.length < 20) {
  throw new Error(`Health gate needs 20 completed builds for ${job}; Prometheus has ${builds.length}.`);
}

// Jenkins Result ordinal is 0 for SUCCESS; every other outcome is non-success.
const successes = builds.filter(({ resultOrdinal }) => resultOrdinal === 0).length;
const rate = successes / builds.length;
console.log(`Health gate: ${successes}/${builds.length} successful (${(rate * 100).toFixed(1)}%) for ${job}.`);
if (rate < 0.9) {
  throw new Error('Health gate blocked production deployment: rolling success rate is below 90%.');
}
