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
        
        // Stage สำหรับ Staging: ต้องรันอัตโนมัติบน branch develop เท่านั้น (ไม่มี input)
        stage('Deploy Staging') {
            when {
                branch 'develop'
            }
            steps {
                echo 'Deploying to staging environment...'
            }
        }
        
        // Stage สำหรับ Production: ต้องรันบน branch main และหยุดรออนุมัติเฉพาะเมื่อเป็น main
        stage('Deploy Production') {
            when {
                branch 'main'
            }
            steps {
                // ย้าย input มาไว้ข้างใน steps หรือใช้ input block ร่วมกับ when ให้ถูกต้อง
                input message: 'Deploy to production?'
                echo 'Deploying to production environment...'
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