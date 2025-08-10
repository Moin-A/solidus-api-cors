pipeline {
    agent any
    stages {
        stage('Install Gems') {
            steps {
                sh 'bundle install'
            }
        }
        stage('DB Setup') {
            steps {
                sh 'rails db:create db:migrate'
            }
        }
        stage('Run Tests') {
            steps {
                sh 'rails test'
            }
        }
    }
}