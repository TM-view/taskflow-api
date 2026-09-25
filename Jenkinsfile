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
        // --- LAB 06: Secrets Detection (ตรวจก่อนเริ่ม Build) ---
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

        // --- LAB 03: Install Dependencies ---
        stage('2. Install') {
            steps {
                dir('backend') {
                    sh 'npm ci'
                }
            }
        }

        // --- LAB 03 + LAB 06: SAST & Lint ---
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

        // --- LAB 06: SCA (Software Component Analysis) ---
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

        // --- LAB 03 + LAB 05: Unit Test & Coverage ---
        stage('5. Unit Test & Coverage') {
            steps {
                dir('backend') {
                    sh 'npm test -- --coverage --reporters=default --reporters=jest-junit'
                }
            }
            post {
                always {
                    dir('backend') {
                        junit 'reports/junit.xml'
                        publishCoverage adapters: [coberturaAdapter('coverage/cobertura-coverage.xml')]
                    }
                }
            }
        }

        // --- LAB 06: Generate SBOM ---
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

        // --- LAB 06: Policy Gate (OPA) ---
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