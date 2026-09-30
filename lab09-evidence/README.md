# Lab 09 run and evidence checklist

## Jenkins setup

1. In Manage Jenkins → Plugins, install the Kubernetes and Prometheus metrics plugins; restart Jenkins after installation.
2. Put Jenkins on the Docker network used by the existing kind cluster. In this setup, both `jenkins` and `taskflow-cluster-control-plane` are on Docker network `kind`; the controller must resolve `taskflow-cluster-control-plane` and reach the API at `https://taskflow-cluster-control-plane:6443`.
3. In Manage Jenkins → Clouds, add a Kubernetes cloud with Kubernetes URL `https://taskflow-control-plane:6443`, the cluster CA and service-account credential from the existing kind setup, Jenkins URL `http://jenkins:8080`, WebSocket enabled, and namespace `jenkins-agents`. Add a Pod Template labeled `k8s-node`, set its concurrency cap to **2**, and use `node:20-alpine` as the `node` container. Configure Prometheus plugin collection interval to 120 seconds and enable per-build metrics if available.
4. Apply the least-privilege namespace resources: `kubectl apply -f k8s/jenkins-agents.yaml`.
5. Create a Pipeline job for this repository with script path `lab09/Jenkinsfile`. The dedicated Jenkinsfile keeps earlier lab configurations intact and assigns the whole Lab 09 run to an ephemeral Kubernetes pod.
6. Watch a run with `kubectl get pods -n jenkins-agents -w`; record the pod's creation, Running state, and deletion after the build.

## Metrics and dashboard

The Prometheus metrics plugin uses the `default_jenkins_` prefix. Set collection interval to 120 seconds and enable **Collect metrics for each run per build** with a maximum age of 168 hours and maximum 20 builds per job. These bounded per-build duration observations support the Lab 09 rolling p95 even if the summary metric is unavailable. Start the monitoring stack on the same Docker network as Jenkins with `docker compose -f monitoring/docker-compose.yml up -d`. This compose file attaches monitoring to the existing Docker network `kind`. Confirm `http://localhost:9090/targets` reports `jenkins` as UP and query `default_jenkins_executors_queue_length` in Prometheus. Grafana is at `http://localhost:3001` (initial lab login `admin` / `admin`; change it before exposing the service). The provisioned dashboard has the three required panels.

The plugin exports build duration as a summary in **milliseconds**, not a histogram. The SLO recording rule converts its p95 quantile to seconds before comparing against 360 seconds. Its queue gauge measures queue length, not per-item wait duration; therefore `JenkinsQueueBacklog` uses a non-empty queue continuously for five minutes as the documented capacity symptom/proxy.

Run `promtool check rules monitoring/jenkins-slo.yml` before starting Prometheus when `promtool` is installed.

## Saturation and recovery evidence

1. Set the Kubernetes pod-template cap to 2. Start 10 builds close together (disable `HOLD_AGENT` for normal builds, or enable it to hold allocated pods deliberately).
2. Save `kubectl get pods -n jenkins-agents -w` output as `load-test-pods-w.txt`; capture queue growth and `JenkinsQueueBacklog` reaching FIRING after five minutes.
3. Increase the cloud/template cap from 2 to 4. Wait for the queue to drain and save the alert becoming inactive.
4. Export the dashboard from Grafana as `grafana-dashboard-export.json`; save alert firing/cleared screenshots and note timestamps and build results in `load-test-timeline.txt`.

Do not fabricate live evidence: the screenshots, pod watch output, and alert history must come from the running lab environment.
