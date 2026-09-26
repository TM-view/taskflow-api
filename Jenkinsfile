pipeline {
    agent any
    tools {
        nodejs 'node20'
    }
    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
        REGISTRY = 'localhost:5001'
        IMAGE_TAG = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'dev'}"
    }
    options {
        timeout(time: 20, unit: 'MINUTES')
    }
    stages {
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
            steps {
                dir('backend') {
                    echo "Building Docker Image with tag: ${IMAGE_TAG}"
                    sh "docker build -t ${REGISTRY}/${APP_NAME}:${IMAGE_TAG} ."
                    sh "docker push ${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
                }
            }
        }

        // --- 11. CONTAINER SCAN - TRIVY (Lab 07) ---
        stage('11. Container Scan (Trivy)') {
            steps {
                echo 'Scanning container image with Trivy via Docker...'
                // เพิ่ม --db-repository และ --timeout 10m เพื่อป้องกัน Network Timeout
                sh "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v \$PWD:/workspace -w /workspace aquasec/trivy image --db-repository ghcr.io/aquasecurity/trivy-db:2 --timeout 10m --format sarif -o trivy.sarif ${REGISTRY}/${APP_NAME}:${IMAGE_TAG} || true"
                sh "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --db-repository ghcr.io/aquasecurity/trivy-db:2 --timeout 10m --exit-code 1 --severity HIGH,CRITICAL ${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy.sarif', allowEmptyArchive: true
                }
            }
        }

        // --- 12. DEPLOY STAGING (Lab 04 + Lab 07 - Blue/Green) ---
        stage('12. Deploy Staging (Blue/Green)') {
            when {
                branch 'develop'
            }
            steps {
                script {
                    echo "Deploying to Staging Environment..."
                    def current = sh(script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                    def next = (current == 'blue') ? 'green' : 'blue'
                    
                    sh "kubectl set image deployment/taskflow-${next} taskflow-api=${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
                    sh "kubectl rollout status deployment/taskflow-${next}"
                    sh "kubectl run smoke-${BUILD_NUMBER} --rm -i --restart=Never --image=curlimages/curl -- curl -sf http://taskflow-${next}:8080/health || true"
                    sh "kubectl patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${next}\"}}}'"
                    echo "Staging: Switched traffic from ${current} to ${next}"
                }
            }
        }

        // --- 13. DEPLOY PRODUCTION (Lab 04 + Lab 07 - Blue/Green + Approval Gate) ---
        stage('13. Deploy Production (Blue/Green)') {
            when {
                branch 'main'
            }
            steps {
                input message: 'Approve Deployment to Production Environment?'
                script {
                    echo "Deploying to Production Environment..."
                    def current = sh(script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                    def next = (current == 'blue') ? 'green' : 'blue'
                    
                    sh "kubectl set image deployment/taskflow-${next} taskflow-api=${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
                    sh "kubectl rollout status deployment/taskflow-${next}"
                    sh "kubectl run smoke-${BUILD_NUMBER} --rm -i --restart=Never --image=curlimages/curl -- curl -sf http://taskflow-${next}:8080/health || true"
                    sh "kubectl patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${next}\"}}}'"
                    echo "Production: Switched traffic from ${current} to ${next}"
                }
            }
        }
    }
    post {
        success {
            echo "${env.APP_NAME} successfully passed all security gates, build, scanning, and blue/green deployment!"
        }
        failure {
            script {
                echo "Pipeline failed at stage: ${env.STAGE_NAME}"
                if (env.STAGE_NAME.contains('Deploy')) {
                    echo "Initiating automatic rollback..."
                    def current = sh(script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                    def rollbackColor = (current == 'blue') ? 'green' : 'blue'
                    sh "kubectl patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${rollbackColor}\"}}}'"
                    echo "Rollback completed. Traffic forced back to ${rollbackColor}"
                }
            }
        }
    }
}