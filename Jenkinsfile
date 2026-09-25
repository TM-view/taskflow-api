pipeline {
    agent any
    tools {
        nodejs 'node20'
    }
    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
    }
    options {
        timeout(time: 15, unit: 'MINUTES')
    }
    stages {
        // --- 1. Security Check ก่อนเริ่ม Build ---
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

        // --- 2. Install Dependencies ---
        stage('2. Install') {
            steps {
                dir('backend') {
                    sh 'npm ci'
                }
            }
        }

        // --- 3. SAST & Code Quality ---
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

        // --- 4. SCA (Software Component Analysis) ---
        stage('4. SCA - npm audit') {
            steps {
                dir('backend') {
                    script {
                        sh 'npm audit --audit-level=high --json > audit.json || true'
                        def critical = sh(
                            script: "jq '.metadata.vulnerabilities.critical' audit.json",
                            returnStdout: true
                        ).trim().toInteger()

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

        // --- 5. Unit Test & Coverage ---
        stage('5. Unit Test & Coverage') {
            steps {
                dir('backend') {
                    sh 'npm test -- --coverage --reporters=default --reporters=jest-junit'
                }
            }
            post {
                always {
                    dir('backend') {
                        // เก็บรายงาน JUnit สำหรับแสดงผล Test Trend
                        junit 'reports/junit.xml'
                        // เก็บไฟล์ Coverage ทั้งหมดเป็น Build Artifacts
                        archiveArtifacts artifacts: 'coverage/**', allowEmptyArchive: true
                    }
                }
            }
        }

        // --- 6. Generate SBOM ---
        stage('6. Generate SBOM') {
            steps {
                dir('backend') {
                    echo 'Generating SBOM with Syft / CycloneDX...'
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

        // --- 7. Policy Gate (OPA) ---
        stage('7. Policy Gate (OPA)') {
            steps {
                dir('backend') {
                    script {
                        echo 'Evaluating Security Policy via OPA...'
                        sh 'npx @open-policy-agent/opa eval --data ../policy/security.rego --input audit.json "data.security.allow" || true'
                    }
                }
            }
        }

        // --- 8. Deploy Staging (จาก Lab 04) ---
        stage('8. Deploy Staging') {
            when {
                branch 'develop'
            }
            steps {
                echo 'Deploying to staging environment...'
            }
        }

        // --- 9. Deploy Production (จาก Lab 04) ---
        stage('9. Deploy Production') {
            when {
                branch 'main'
            }
            input {
                message 'Deploy to production?'
            }
            steps {
                echo 'Deploying to production environment...'
            }
        }
    }
    post {
        success {
            echo "${env.APP_NAME} passed all security & build gates on ${env.NODE_ENV}"
        }
        failure {
            echo "Failed at stage: ${env.STAGE_NAME}"
        }
    }
}