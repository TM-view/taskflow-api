pipeline {
    agent {
        kubernetes {
            defaultContainer 'node'
            yaml '''
apiVersion: v1
kind: Pod
metadata:
  namespace: jenkins-agents
spec:
  serviceAccountName: jenkins
  restartPolicy: Never
  containers:
  - name: node
    image: node:20-bookworm-slim
    command: ['cat']
    tty: true
    resources:
      requests: {cpu: 500m, memory: 1Gi}
      limits: {cpu: '2', memory: 3Gi}
  - name: buildkit
    image: moby/buildkit:v0.20.2-rootless
    command: ['cat']
    tty: true
    securityContext:
      runAsUser: 1000
      runAsGroup: 1000
      seccompProfile:
        type: Unconfined
    resources:
      requests: {cpu: 500m, memory: 1Gi}
      limits: {cpu: '2', memory: 3Gi}
  - name: trivy
    image: aquasec/trivy:0.69.3
    command: ['cat']
    tty: true
    resources:
      requests: {cpu: 100m, memory: 256Mi}
      limits: {cpu: '1', memory: 1Gi}
  - name: kubectl
        image: bitnamilegacy/kubectl:1.33
    command: ['cat']
    tty: true
    resources:
      requests: {cpu: 100m, memory: 128Mi}
      limits: {cpu: 500m, memory: 512Mi}
  - name: gitleaks
    image: zricethezav/gitleaks:v8.24.2
    command: ['cat']
    tty: true
    resources:
      requests: {cpu: 100m, memory: 128Mi}
      limits: {cpu: 500m, memory: 512Mi}
  - name: semgrep
    image: semgrep/semgrep:1.144.0
    command: ['cat']
    tty: true
    resources:
      requests: {cpu: 250m, memory: 512Mi}
      limits: {cpu: '1', memory: 2Gi}
'''
        }
    }
    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
        K8S_REGISTRY = 'registry:5000'
        LOCALSTACK_ENDPOINT = 'http://localstack.default.svc.cluster.local:4566'
        AWS_DEFAULT_REGION = 'us-east-1'
    }
    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }
    parameters {
        booleanParam(
            name: 'TEST_ROLLOUT_FAILURE',
            defaultValue: false,
            description: 'On develop only, deploy a missing image to test rollout failure and automatic rollback'
        )
        booleanParam(
            name: 'REPLACE_LOCALSTACK_INSTANCE',
            defaultValue: false,
            description: 'On lab08 only, replace the Terraform-managed Docker SSH host once'
        )
    }
    stages {
        stage('0. Validate Rollout Test Mode') {
            when {
                expression { params.TEST_ROLLOUT_FAILURE && env.BRANCH_NAME != 'develop' }
            }
            steps {
                script {
                    error('TEST_ROLLOUT_FAILURE is allowed only on the develop branch')
                }
            }
        }

        // --- 2. INSTALL DEPENDENCIES (Lab 03) ---
        stage('2. Install Dependencies') {
            steps {
                dir('backend') {
                    sh 'npm ci'
                }
            }
        }

        // --- 3. SAST & CODE QUALITY (Lab 03 + Lab 06) ---
        stage('3. Parallel Quality Gates') {
            failFast true
            parallel {
                stage('Lint and SAST') {
                    steps {
                        dir('backend') {
                            sh 'npx eslint --rule "prettier/prettier: off" "{src,apps,libs,test}/**/*.ts"'
                            container('semgrep') {
                                sh 'semgrep scan --error --config p/owasp-top-ten --config p/nodejs --sarif --output semgrep.sarif src/'
                            }
                        }
                    }
                    post {
                            always { dir('backend') { archiveArtifacts artifacts: 'semgrep.sarif', allowEmptyArchive: true } }
                    }
                }
                stage('Unit Tests') {
                    steps { dir('backend') { sh 'npx jest --coverage --reporters=default --reporters=jest-junit' } }
                    post {
                        always {
                            dir('backend') {
                                junit 'reports/junit.xml'
                                archiveArtifacts artifacts: 'coverage/**', allowEmptyArchive: true
                            }
                        }
                    }
                }
                stage('SCA') {
                    steps { dir('backend') { sh 'npm audit --audit-level=high --json > audit.json' } }
                    post {
                        always { dir('backend') { archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true } }
                    }
                }
                stage('Secrets Detection') {
                    steps {
                        container('gitleaks') {
                            sh 'gitleaks detect --source . --verbose --report-path gitleaks-report.json'
                        }
                    }
                    post {
                        always { archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true }
                    }
                }
            }
        }

        // --- 6. SONARQUBE ANALYSIS & QUALITY GATE (Lab 05) ---
        stage('6. SonarQube Analysis') {
            steps {
                dir('backend') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        withSonarQubeEnv('SonarQube') {
                            sh 'npx sonar-scanner -Dsonar.projectKey=taskflow-api -Dsonar.sources=src -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info -Dsonar.token="$SONAR_TOKEN"'
                        }
                    }
                }
            }
        }
        stage('7. Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // --- 8. GENERATE SBOM (Lab 06) ---
        stage('8. Generate SBOM') {
            steps {
                dir('backend') {
                    echo 'Generating SBOM with CycloneDX...'
                    sh 'npx @cyclonedx/cyclonedx-npm --output-file bom.cdx.json'
                }
            }
            post {
                always {
                    dir('backend') {
                        archiveArtifacts artifacts: 'bom.cdx.json', allowEmptyArchive: true
                    }
                }
            }
        }

        // --- 9. POLICY GATE - OPA (Lab 06) ---
        stage('9. Policy Gate (OPA)') {
            steps {
                dir('backend') {
                    script {
                        echo 'Evaluating Security Policy via OPA...'
                        sh 'npx @open-policy-agent/opa eval --format raw --data ../policy/security.rego --input audit.json "data.security.allow" > opa-result.txt'
                        sh 'grep -qx true opa-result.txt'
                    }
                }
            }
        }

        // --- 10. BUILD DOCKER IMAGE & PUSH (Lab 07) ---   
        stage('10. Build Image') {
            steps {
                dir('backend') {
                    script {
                        env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                        echo "Building Docker Image with tag: ${env.IMAGE_TAG}"
                        container('buildkit') {
                            withEnv([
                                "IMAGE_REF=${K8S_REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}",
                                "BUILDKITD_FLAGS=--oci-worker-no-process-sandbox --config ${env.WORKSPACE}/ci/buildkitd.toml"
                            ]) {
                                sh '''
                                    set -eu
                                    buildctl-daemonless.sh build \\
                                      --frontend dockerfile.v0 \\
                                      --local context=. \\
                                      --local dockerfile=. \\
                                      --output "type=image,name=${IMAGE_REF},push=true,registry.insecure=true"
                                '''
                            }
                        }
                    }
                }
            }
        }

        // --- 11. CONTAINER SCAN - TRIVY (Lab 07) ---
        stage('11. Container Scan (Trivy)') {
            steps {
                container('trivy') {
                    sh "trivy image --insecure --image-src remote --timeout 10m --format sarif --output trivy.sarif ${K8S_REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}"
                    sh "trivy image --insecure --image-src remote --skip-db-update --exit-code 1 --severity HIGH,CRITICAL ${K8S_REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}"
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy.sarif', allowEmptyArchive: true
                }
            }
        }

        // --- 12. IAC LINT & VALIDATE & SCAN (Lab 08) ---
        stage('12. Prepare Lab 08 SSH Key') {
            when { branch 'lab08' }
            steps {
                script {
                    sh 'mkdir -p .lab08; if [ ! -f .lab08/taskflow-api ]; then ssh-keygen -q -t ed25519 -N "" -f .lab08/taskflow-api; fi; chmod 600 .lab08/taskflow-api'
                    env.TF_VAR_ssh_public_key = readFile('.lab08/taskflow-api.pub').trim()
                }
            }
        }

        stage('13. IaC Lint & Validate') {
            when { branch 'lab08' }
            parallel {
                stage('Terraform Validate') {
                    steps {
                        dir('infra/terraform') {
                            sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 fmt -check -recursive'
                            // Keep the provider cache, but remove stale backend metadata from a prior remote init.
                            sh 'rm -f .terraform/terraform.tfstate .terraform/terraform.tfstate.backup'
                            sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 init -backend=false'
                            sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 validate'
                        }
                    }
                }
                stage('Ansible Lint') {
                    steps {
                        sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/ansible" cytopia/ansible-lint:latest playbook.yml'
                    }
                }
            }
        }

        stage('14. IaC Security Scan') {
            when { branch 'lab08' }
            steps {
                sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE" aquasec/tfsec:latest "$WORKSPACE/infra/terraform" --format json > tfsec-report.json'
                sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE" bridgecrew/checkov:latest -d "$WORKSPACE/infra/terraform" -o json > checkov-report.json'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'tfsec-report.json, checkov-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('15. Validate Docker Host and Prepare Remote State') {
            when { branch 'lab08' }
            steps {
                sh '''
                    if ! docker info >/dev/null 2>&1; then
                        echo "Jenkins cannot reach the Docker engine required to provision the Lab 08 host." >&2
                        exit 1
                    fi

                    if ! docker image inspect ubuntu:22.04 >/dev/null 2>&1; then
                        docker pull ubuntu:22.04
                    fi

                    if ! docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                        amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                        s3api head-bucket --bucket taskflow-tfstate >/dev/null 2>&1; then
                        docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                            amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                            s3api create-bucket --bucket taskflow-tfstate
                    fi

                    docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                        amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                        s3api put-bucket-versioning --bucket taskflow-tfstate \
                        --versioning-configuration Status=Enabled

                    versioning=$(docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                        amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                        s3api get-bucket-versioning --bucket taskflow-tfstate \
                        --query Status --output text)
                    if [ "$versioning" != Enabled ]; then
                        echo "Remote state bucket versioning is not enabled." >&2
                        exit 1
                    fi

                    state_key=lab/terraform.tfstate
                    legacy_state_key=taskflow/lab08/terraform.tfstate
                    if ! docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                        amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                        s3api head-object --bucket taskflow-tfstate --key "$state_key" >/dev/null 2>&1; then
                        if docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                            amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                            s3api head-object --bucket taskflow-tfstate --key "$legacy_state_key" >/dev/null 2>&1; then
                            echo "Migrating existing Terraform state to s3://taskflow-tfstate/$state_key"
                            docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                                amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                                s3api copy-object --bucket taskflow-tfstate --key "$state_key" \
                                --copy-source "taskflow-tfstate/$legacy_state_key"
                        fi
                    fi
                '''
            }
        }

        stage('16. Terraform Plan') {
            when { branch 'lab08' }
            steps {
                dir('infra/terraform') {
                    sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 init -input=false -reconfigure'
                    script {
                        def replacementArg = params.REPLACE_LOCALSTACK_INSTANCE ? '-replace=docker_container.taskflow_host' : ''
                        sh "docker run --rm --volumes-from jenkins -w \"\$WORKSPACE/infra/terraform\" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 plan -input=false ${replacementArg} -out=tfplan"
                    }
                    sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 show -no-color tfplan > plan-summary.txt'
                }
            }
            post {
                always {
                    dir('infra/terraform') {
                        archiveArtifacts artifacts: 'tfplan, plan-summary.txt', allowEmptyArchive: true
                    }
                }
            }
        }

        stage('17. Approve Terraform Apply') {
            when { branch 'lab08' }
            steps {
                sh 'cat infra/terraform/plan-summary.txt'
                input message: 'Review the plan summary in this build log, then approve the Lab 08 apply.'
            }
        }
        
        stage('18. Terraform Apply') {
            when { branch 'lab08' }
            steps {
                dir('infra/terraform') {
                    sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 apply -input=false -auto-approve tfplan'
                }
                script {
                    def instanceIp = sh(
                        script: 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 output -raw instance_ip',
                        returnStdout: true
                    ).trim()

                    def ansibleHost = sh(
                        script: 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 output -raw ansible_host',
                        returnStdout: true
                    ).trim()

                    def sshPort = sh(
                        script: 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 output -raw ansible_port',
                        returnStdout: true
                    ).trim()

                    if (!sshPort) {
                        error "Terraform did not return the SSH port for the Lab 08 Docker host."
                    }

                    echo "Detected SSH port: ${sshPort}"

                    writeFile file: 'infra/ansible/inventory.ini', text: """[taskflow]
        ${ansibleHost} ansible_port=${sshPort} ansible_user=root ansible_ssh_private_key_file=${env.WORKSPACE}/.lab08/taskflow-api ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
        """

                    echo "Terraform provisioned the Lab 08 host at ${instanceIp}"
                }
            }
        }

        stage('19. Configure Host with Ansible') {
            when { branch 'lab08' }
            steps {
                sh '''
                    for attempt in $(seq 1 60); do
                        if docker run --rm --add-host=host.docker.internal:host-gateway --volumes-from jenkins \
                            -w "$WORKSPACE" --entrypoint ansible cytopia/ansible:latest-tools all \
                            -i infra/ansible/inventory.ini -m raw -a \
                            'if command -v python3 >/dev/null 2>&1; then echo PYTHON_PRESENT; else apt-get update && apt-get install -y python3; fi' -o; then
                            break
                        fi
                        if [ "$attempt" -eq 60 ]; then
                            echo "Timed out waiting for SSH and Python bootstrap on the Terraform-managed Docker host." >&2
                            exit 1
                        fi
                        sleep 3
                    done
                '''
                sh "docker run --rm --add-host=host.docker.internal:host-gateway --volumes-from jenkins -w \"${env.WORKSPACE}\" --entrypoint ansible-playbook cytopia/ansible:latest-tools -i infra/ansible/inventory.ini infra/ansible/playbook.yml --extra-vars 'taskflow_image=${REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}'"
            }
        }

        stage('20. Destroy Lab 08 Infrastructure') {
            when { branch 'lab08' }
            steps {
                input message: 'After saving the plan and apply evidence, approve Terraform destroy to leave no lab resources running.'
                dir('infra/terraform') {
                    sh 'docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 destroy -input=false -auto-approve'
                    sh 'test -z "$(docker run --rm --volumes-from jenkins -w "$WORKSPACE/infra/terraform" -e TF_VAR_ssh_public_key -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION hashicorp/terraform:1.12.2 state list)"'
                }
                sh '''
                    docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
                        amazon/aws-cli:latest --endpoint-url "$LOCALSTACK_ENDPOINT" \
                        s3api delete-object --bucket taskflow-tfstate --key taskflow/lab08/terraform.tfstate
                '''
            }
        }

        // --- 16. DEPLOY STAGING (Lab 04 + Lab 07 - Blue/Green) ---
        stage('21. Deploy Staging (Blue/Green)') {
            when {
                branch 'develop'
            }
            steps {
                container('kubectl') {
                    withCredentials([file(credentialsId: 'jenkins-kubeconfig', variable: 'KUBECONFIG')]) {
                    script {
                    echo "Deploying to Staging Environment..."

                    sh "kubectl get svc taskflow -o yaml > svc-before-${BUILD_NUMBER}.yaml"

                    def current = sh(script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                    def next = (current == 'blue') ? 'green' : 'blue'
                    env.DEPLOY_PREVIOUS_COLOR = current
                    env.DEPLOY_TARGET_COLOR = next
                    env.DEPLOY_PREVIOUS_IMAGE = sh(
                        script: "kubectl get deployment/taskflow-${next} -o jsonpath='{.spec.template.spec.containers[0].image}'",
                        returnStdout: true
                    ).trim()

                    def deployImage = params.TEST_ROLLOUT_FAILURE
                        ? "${K8S_REGISTRY}/${APP_NAME}:missing-${BUILD_NUMBER}"
                        : "${K8S_REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}"
                    if (params.TEST_ROLLOUT_FAILURE) {
                        echo "TEST_ROLLOUT_FAILURE enabled; intentionally deploying ${deployImage}"
                    }

                    sh "kubectl set image deployment/taskflow-${next} taskflow-api=${deployImage}"
                    sh "kubectl rollout status deployment/taskflow-${next} --timeout=180s"
                    sh "kubectl run smoke-${BUILD_NUMBER} --rm -i --restart=Never --image=curlimages/curl:8.12.1 --image-pull-policy=IfNotPresent -- curl -fsS http://taskflow-${next}:3000/"
                    sh "kubectl set selector service/taskflow app=taskflow-api,color=${next}"

                    sh "kubectl get svc taskflow -o yaml > svc-after-${BUILD_NUMBER}.yaml"

                    sh "diff svc-before-${BUILD_NUMBER}.yaml svc-after-${BUILD_NUMBER}.yaml > svc-diff-${BUILD_NUMBER}.txt || true"
                    sh "cat svc-diff-${BUILD_NUMBER}.txt"

                    echo "Staging: Switched traffic from ${current} to ${next}"
                    }
                    }
                }
            }
            post {
                failure {
                    container('kubectl') {
                    withCredentials([file(credentialsId: 'jenkins-kubeconfig', variable: 'KUBECONFIG')]) {
                    script {
                        echo 'Automatic rollback firing for failed staging deployment'
                        if (env.DEPLOY_PREVIOUS_COLOR) {
                            echo "ROLLBACK: restoring Service selector to ${env.DEPLOY_PREVIOUS_COLOR}"
                            sh "kubectl set selector service/taskflow app=taskflow-api,color=${env.DEPLOY_PREVIOUS_COLOR}"
                        }
                        if (env.DEPLOY_TARGET_COLOR && env.DEPLOY_PREVIOUS_IMAGE) {
                            echo "ROLLBACK: restoring ${env.DEPLOY_TARGET_COLOR} image to ${env.DEPLOY_PREVIOUS_IMAGE}"
                            sh "kubectl set image deployment/taskflow-${env.DEPLOY_TARGET_COLOR} taskflow-api=${env.DEPLOY_PREVIOUS_IMAGE}"
                            sh "kubectl rollout status deployment/taskflow-${env.DEPLOY_TARGET_COLOR} --timeout=180s"
                        }
                        sh "kubectl get service taskflow -o custom-columns='NAME:.metadata.name,COLOR:.spec.selector.color'"
                        sh 'kubectl get endpoints taskflow -o wide'
                    }
                    }
                    }
                }
                always {
                    archiveArtifacts artifacts: 'svc-before-*.yaml, svc-after-*.yaml, svc-diff-*.txt', allowEmptyArchive: true
                }
            }
        }

        stage('21.5 Pipeline Health Gate') {
            when { branch 'main' }
            steps {
                sh 'node ci/pipeline-health.mjs'
            }
        }

        // --- 17. DEPLOY PRODUCTION (Lab 04 + Lab 07 - Blue/Green + Approval Gate) ---
        stage('22. Deploy Production (Blue/Green)') {
            when {
                branch 'main'
            }
            steps {
                container('kubectl') {
                withCredentials([file(credentialsId: 'jenkins-kubeconfig', variable: 'KUBECONFIG')]) {
                input message: 'Approve Deployment to Production Environment?'
                script {
                    echo "Deploying to Production Environment..."
                    def current = sh(script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                    def next = (current == 'blue') ? 'green' : 'blue'
                    
                    env.DEPLOY_PREVIOUS_COLOR = current
                    env.DEPLOY_NEXT_COLOR = next
                    
                    echo "Current Color: ${current} -> Target Color: ${next}"

                    sh "kubectl set image deployment/taskflow-${next} taskflow-api=${K8S_REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}"
                    sh "kubectl rollout status deployment/taskflow-${next} --timeout=180s"
                    
                    sh "kubectl run smoke-${BUILD_NUMBER} --rm -i --restart=Never --image=curlimages/curl:8.12.1 --image-pull-policy=IfNotPresent -- curl -fsS http://taskflow-${next}:3000/"
                    
                    sh "kubectl set selector service/taskflow app=taskflow-api,color=${next}"
                    echo "Production: Switched traffic from ${current} to ${next}"
                }
                }
                }
            }
            post {
                failure {
                    container('kubectl') {
                    withCredentials([file(credentialsId: 'jenkins-kubeconfig', variable: 'KUBECONFIG')]) {
                    script {
                        echo "--------------------------------------------------"
                        echo "Deploy Failed! Initiating Automatic Rollback..."
                        
                        if (env.DEPLOY_PREVIOUS_COLOR) {
                            echo "Forcing traffic back to previous color: ${env.DEPLOY_PREVIOUS_COLOR}"
                            sh "kubectl set selector service/taskflow app=taskflow-api,color=${env.DEPLOY_PREVIOUS_COLOR}"
                            echo "Rollback Completed Successfully. Active Color: ${env.DEPLOY_PREVIOUS_COLOR}"
                        } else {
                            echo "Rollback skipped: DEPLOY_PREVIOUS_COLOR not defined."
                        }
                        echo "--------------------------------------------------"
                    }
                    }
                    }
                }
            }
        }
    }
    post {
        success {
            emailext(to: '$DEFAULT_RECIPIENTS', subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Branch: ${env.BRANCH_NAME ?: 'unknown'}\nCommit: ${env.GIT_COMMIT ?: 'unknown'}\nBuild: ${env.BUILD_URL}")
        }
        failure {
            emailext(to: '$DEFAULT_RECIPIENTS', subject: "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Branch: ${env.BRANCH_NAME ?: 'unknown'}\nCommit: ${env.GIT_COMMIT ?: 'unknown'}\nBuild: ${env.BUILD_URL}")
        }
        always {
            script {
                if (env.BRANCH_NAME == 'lab08') {
                    sh 'rm -rf .lab08'
                }
            }
        }
    }
}
