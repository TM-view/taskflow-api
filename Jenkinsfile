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
        timeout(time: 10, unit: 'MINUTES')
        // A hung npm install or test run must not hold the executor forever
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
        stage('Unit Test') {
            steps {
                dir('backend') {
                    sh 'npm test'
                }
            }
        }
    }
    post {
        success {
            echo "${env.APP_NAME} passed on ${env.NODE_ENV}"
        }
        failure {
            echo "Failed at stage: ${env.STAGE_NAME}"
        }
        always {
            dir('backend') {
                archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true
            }
        }
    }
}