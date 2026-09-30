pipeline {
    agent any
    tools {
        nodejs 'node20'
    }
    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
        REGISTRY = '127.0.0.1:5001'
        K8S_REGISTRY = 'registry:5000'
        KUBECONFIG = '/var/jenkins_home/.kube/config'
        LOCALSTACK_ENDPOINT = 'http://host.docker.internal:4566'
        AWS_ACCESS_KEY_ID = 'test'
        AWS_SECRET_ACCESS_KEY = 'test'
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

        // --- 1. SECRETS DETECTION (Lab 06) ---
        stage('1. Secrets Detection') {
            steps {
                echo 'Running Gitleaks secrets detection...'
                sh 'npx gitleaks detect --source . --verbose --report-path gitleaks-report.json || true'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
                }
            }
        }

        // --- 2. INSTALL DEPENDENCIES (Lab 03) ---
        stage('2. Install') {
            steps {
                dir('backend') {
                    sh 'npm ci'
                }
            }
        }

        // --- 3. SAST & CODE QUALITY (Lab 03 + Lab 06) ---
        stage('3. SAST & Lint') {
            steps {
                dir('backend') {
                    echo 'Running Lint and SAST Security Analysis...'
                    sh 'npm run lint || true'
                    sh 'npx eslint --plugin security src/ -f json -o eslint-sarif.json || true'
                    sh 'npx semgrep --config=p/owasp-top-ten --config=p/nodejs --sarif -o semgrep.sarif src/ || true'
                }
            }
            post {
                always {
                    dir('backend') {
                        archiveArtifacts artifacts: 'eslint-sarif.json, semgrep.sarif', allowEmptyArchive: true
                    }
                }
            }
        }

        // --- 4. SCA - SOFTWARE COMPONENT ANALYSIS (Lab 06) ---
        stage('4. SCA - npm audit') {
            steps {
                dir('backend') {
                    script {
                        sh 'npm audit --audit-level=high --json > audit.json || true'
                        
                        def criticalStr = sh(
                            script: "node -e \"const fs = require('fs'); const data = JSON.parse(fs.readFileSync('audit.json')); console.log(data.metadata?.vulnerabilities?.critical || 0);\"",
                            returnStdout: true
                        ).trim()
                        
                        def critical = criticalStr.toInteger()

                        if (critical > 0) {
                            error("Blocking: ${critical} critical vulnerabilities found")
                        }
                        echo "SCA passed with 0 critical vulnerabilities (warnings allowed)"
                    }
                }
            }
            post {
                always {
                    dir('backend') {
                        archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true
                    }
                }
            }
        }

        // --- 5. UNIT TEST & COVERAGE (Lab 03 + Lab 05) ---
        stage('5. Unit Test & Coverage') {
            steps {
                dir('backend') {
                    sh 'npx jest --coverage --reporters=default --reporters=jest-junit'
                }
            }
            post {
                always {
                    dir('backend') {
                        junit 'reports/junit.xml'
                        archiveArtifacts artifacts: 'coverage/**', allowEmptyArchive: true
                    }
                }
            }
        }

        // --- 6. SONARQUBE ANALYSIS & QUALITY GATE (Lab 05) ---
        stage('6. SonarQube Analysis') {
            steps {
                dir('backend') {
                    withSonarQubeEnv('SonarQube') {
                        sh 'npx sonar-scanner -Dsonar.projectKey=taskflow-api -Dsonar.sources=src -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info || true'
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
                    sh 'npx @cyclonedx/cyclonedx-npm --output-file bom.cdx.json || true'
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
                        sh 'npx @open-policy-agent/opa eval --data ../policy/security.rego --input audit.json "data.security.allow" || true'
                    }
                }
            }
        }

        // --- 10. BUILD DOCKER IMAGE & PUSH (Lab 07) ---   
        stage('10. Build Image') {
            // The lab10 branch is used for pipeline email validation on a Kubernetes-only agent.
            // Keep Docker image builds enabled on the deployment branches.
            when { not { branch 'lab10' } }
            steps {
                dir('backend') {
                    script {
                        env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                        echo "Building Docker Image with tag: ${env.IMAGE_TAG}"
                        sh "docker build -t ${REGISTRY}/${APP_NAME}:${env.IMAGE_TAG} ."
                        sh "docker push ${REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}"
                        sh """
                            set -eu
                            node=taskflow-cluster-control-plane
                            if ! docker inspect "\$node" >/dev/null 2>&1; then
                                echo "Required Kind node container '\$node' does not exist." >&2
                                exit 1
                            fi

                            if [ "\$(docker inspect -f '{{.State.Running}}' "\$node")" != true ]; then
                                echo "Starting stopped Kind node container '\$node'."
                                docker start "\$node" >/dev/null
                            fi

                            for attempt in \$(seq 1 60); do
                                if docker exec "\$node" ctr version >/dev/null 2>&1; then
                                    break
                                fi
                                if [ "\$attempt" -eq 60 ]; then
                                    echo "Timed out waiting for containerd in '\$node'." >&2
                                    docker logs --tail 50 "\$node" >&2 || true
                                    exit 1
                                fi
                                sleep 2
                            done

                            docker exec "\$node" ctr -n k8s.io images pull --plain-http ${K8S_REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}
                        """
                    }
                }
            }
        }

        // --- 11. CONTAINER SCAN - TRIVY (Lab 07) ---
        stage('11. Container Scan (Trivy)') {
            when { not { branch 'lab10' } }
            steps {
                echo 'Scanning container image with Trivy via Docker...'
                sh "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ aquasec/trivy image --scanners vuln --timeout 10m --format sarif ${REGISTRY}/${APP_NAME}:${env.IMAGE_TAG} > trivy.sarif"
                sh "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ -v \$PWD:/workspace -w /workspace aquasec/trivy image --scanners vuln --skip-db-update --exit-code 1 --severity HIGH,CRITICAL ${REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}"
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
            post {
                failure {
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
            post {
                failure {
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
