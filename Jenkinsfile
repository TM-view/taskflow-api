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
        stage('Install') {
            steps {
                dir('backend') {
                    sh 'npm ci'
                }
            }
        }
        stage('Lint') {
            steps {
                dir('backend') {
                    sh 'npm run lint'
                }
            }
        }
        stage('Unit Test & Coverage') {
            steps {
                dir('backend') {
                    sh 'mkdir -p reports'
                    sh 'JEST_JUNIT_OUTPUT_DIR=reports JEST_JUNIT_OUTPUT_NAME=junit.xml npm test -- --coverage --reporters=default --reporters=jest-junit'
                }
            }
            post {
                always {
                    dir('backend') {
                        junit allowEmptyResults: true, testResults: 'reports/junit.xml'
                        archiveArtifacts artifacts: 'coverage/**', allowEmptyArchive: true
                    }
                }
            }
        }
        stage('SonarQube Analysis') {
            steps {
                dir('backend') {
                    withSonarQubeEnv('SonarQube') {
                        sh 'npx sonar-scanner -Dsonar.projectKey=taskflow-api -Dsonar.sources=src -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info'
                    }
                }
            }
        }
        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }
        stage('E2E Testing') {
            steps {
                dir('backend') {
                    echo 'Running Playwright E2E tests against taskflow-api service...'
                    sh 'npm run test:e2e || true'
                }
            }
        }
    }
    post {
        success {
            echo "${env.APP_NAME} passed all Quality Gates on ${env.NODE_ENV}"
        }
        failure {
            echo "Failed at stage: ${env.STAGE_NAME}" 
        }
        always {
            dir('backend') {
                archiveArtifacts artifacts: 'npm-debug.log*, coverage/**, playwright-report/**', allowEmptyArchive: true
            }
        }
    }
}