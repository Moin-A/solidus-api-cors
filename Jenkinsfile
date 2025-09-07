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
        
        stage('Deploy') {
            steps {
                echo 'Restarting local server...'
                script {
                    // Kill existing server process
                    sh '''
                        # Find and kill the process running on your port
                        PID=$(lsof -ti:3000) || true  # Replace 3000 with your port
                        if [ ! -z "$PID" ]; then
                            echo "Killing existing server process: $PID"
                            kill -9 $PID || true
                            sleep 2
                        fi
                        
                        # Start the server in background
                        echo "Starting new server..."
                        cd ${WORKSPACE}
                        nohup rails server -p 3000 -e development > /dev/null 2>&1 &
                        
                        # Give server time to start
                        sleep 5
                        echo "Server restarted successfully"
                    '''
                }
            }
        }
    }
}