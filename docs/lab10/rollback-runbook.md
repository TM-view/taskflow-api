# Production rollback runbook

Use this when the `Deploy Production (Blue/Green)` stage fails or the post-deploy smoke check is unhealthy. The production Service is `taskflow`; deployments are `taskflow-blue` and `taskflow-green` in the current kubectl context's default namespace.

1. Open the failed Jenkins build and confirm that `Pipeline Health Gate` passed and that failure occurred during/after rollout. Do not approve a retry while the health gate is red.
2. Inspect the active Service selector and both deployment images:

   ```sh
   kubectl get svc taskflow -o jsonpath='{.spec.selector.color}{"\n"}'
   kubectl get deploy taskflow-blue taskflow-green -o wide
   kubectl get pods -l app=taskflow-api -o wide
   ```

3. Read `Current Color` and `Target Color` from the Jenkins console. Set `PREVIOUS_COLOR` to the color that was serving before this build (`blue` or `green`). If the selector already points to the new color, restore traffic immediately:

   ```sh
   PREVIOUS_COLOR=blue # replace with the value recorded in the build log
   kubectl set selector service/taskflow app=taskflow-api,color="$PREVIOUS_COLOR"
   kubectl get endpoints taskflow -o wide
   ```

4. Verify the active deployment is ready and the Service responds from inside the cluster:

   ```sh
   kubectl rollout status "deployment/taskflow-$PREVIOUS_COLOR" --timeout=180s
   kubectl run "rollback-smoke-$(date +%s)" --rm -i --restart=Never \
     --image=curlimages/curl:8.12.1 -- curl -fsS "http://taskflow-$PREVIOUS_COLOR:3000/"
   ```

5. If the previous deployment is unhealthy, keep the Service on the last known ready color, stop further production builds, and page the service owner. Do not delete either deployment during incident response.
6. Record the failed build URL, commit, previous/target colors, image tags, command output, and recovery time. Fix the cause on a branch and require the normal gates and approval before retrying production.

The Jenkinsfile also attempts to restore the previous Service selector automatically when the production stage fails. Confirm the selector and endpoints yourself; the manual steps above are the recovery path if the automatic rollback did not complete.
