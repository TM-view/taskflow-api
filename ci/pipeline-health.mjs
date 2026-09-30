import { evaluateBuildHealth } from './pipeline-health-lib.mjs';

const baseUrl = process.env.PROMETHEUS_URL;
const job = process.env.PROMETHEUS_JENKINS_JOB || process.env.JOB_NAME || 'taskflow-multibranch/main';
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

// Jenkins Result ordinal is 0 for SUCCESS; every other outcome is non-success.
const health = evaluateBuildHealth(payload.data.result, { currentBuild, limit: 20, minimumRate: 0.9 });
console.log(`Health gate: ${health.successCount}/${health.buildCount} successful (${(health.successRate * 100).toFixed(1)}%) for ${job}.`);
if (health.blocked) throw new Error(health.reason);
