# Production rollback runbook

Use this when the Jenkins `Deploy Production (Blue/Green)` stage fails or the post-deploy smoke check fails. The Kubernetes objects are in the cluster and namespace selected by the `jenkins-kubeconfig` Jenkins Secret file credential. The Service is `taskflow`; deployments are `taskflow-blue` and `taskflow-green`.

1. Open the failed Jenkins build. Record the build URL, commit, `Current Color`, `Target Color`, and image tag from the console. The pipeline attempts automatic selector rollback after deployment-stage failures.
2. From an operator terminal, select the same kube context and namespace as the production workload, then inspect the current traffic selector and both rollouts:

   ```sh
   kubectl config current-context
   kubectl get svc taskflow -o jsonpath='{.spec.selector.color}{"\\n"}'
   kubectl get deploy taskflow-blue taskflow-green -o wide
   kubectl get pods -l app=taskflow-api -o wide
   kubectl get endpoints taskflow -o wide
   ```

3. Use `Current Color` from the build log as `PREVIOUS_COLOR` (`blue` or `green`). If the Service selector points at the failed target, immediately switch traffic back:

   ```sh
   PREVIOUS_COLOR=blue # replace with the recorded Current Color
   kubectl set selector service/taskflow app=taskflow-api,color="$PREVIOUS_COLOR"
   kubectl get endpoints taskflow -o wide
   ```

4. Confirm the previous deployment is ready and answers a smoke request:

   ```sh
   kubectl rollout status "deployment/taskflow-$PREVIOUS_COLOR" --timeout=180s
   kubectl run "rollback-smoke-$(date +%s)" --rm -i --restart=Never \
     --image=curlimages/curl:8.12.1 -- curl -fsS "http://taskflow-$PREVIOUS_COLOR:3000/"
   ```

5. If the previous color is unhealthy, keep production traffic on the last known ready color, stop approving production builds, and page the service owner. Do not delete either deployment during incident response.
6. Record command output, image tags, build URL, commit, previous/target colors, and recovery time. Fix the cause on a branch; rerun the gates before requesting another production approval.
