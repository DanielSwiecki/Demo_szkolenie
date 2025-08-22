pipeline {
  agent any
  options { timestamps() }

  environment { IMAGE_NAME = "green-app" }   

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.SHORT_SHA     = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          env.ACTUAL_BRANCH = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
          echo "Branch: ${env.ACTUAL_BRANCH}, Commit: ${env.SHORT_SHA}"
        }
      }
    }

    stage('Build (Docker)') {
      steps {
        sh '''
          docker build -t ${IMAGE_NAME}:${SHORT_SHA} . 
          docker tag ${IMAGE_NAME}:${SHORT_SHA} ${IMAGE_NAME}:latest
          docker images | head -n 10
        '''
      }
    }

    stage('Staging (Terraform)') {
      steps {
        sh """
          set -e
          cd infra
          terraform init -input=false                      
          terraform apply -auto-approve \
            -var image_name=${IMAGE_NAME} -var tag=${SHORT_SHA} 
          sleep 6
          docker run --rm --network=green_net curlimages/curl:8.8.0 \
            -fsS http://green-app-staging:5000/health
        """
      }
    }

    stage('Deploy PROD (Docker)') {
      steps {
        sh '''
          docker rm -f green-app-prod || true
          docker run -d --name green-app-prod -p 3000:5000 ${IMAGE_NAME}:${SHORT_SHA}
          sleep 6
          docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        '''
      }
    }

    stage('Smoke Tests + Report') {
      steps {
        sh '''
          set -e
          mkdir -p report

          # staging przez nazwę w tej samej sieci
          STAGING_HEALTH=$(docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:5000/health || echo FAIL)
          STAGING_ROOT=$(docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:5000/ || echo FAIL)

          # prod przez hostowy port 3000 (ważne: sieć hosta!)
          PROD_HEALTH=$(docker run --rm --network=host curlimages/curl:8.8.0 -fsS http://localhost:3000/health || echo FAIL)  
          PROD_ROOT=$(docker run --rm --network=host curlimages/curl:8.8.0 -fsS http://localhost:3000/ || echo FAIL)          

          # raport (heredoc – tag kończy się w kolumnie 1!)
          cp report_template.html report/index.html
          sed -i "s/__SHORT_SHA__/$SHORT_SHA/" report/index.html
          sed -i "s|__STAGING_HEALTH__|$STAGING_HEALTH|" report/index.html
          sed -i "s|__STAGING_ROOT__|$STAGING_ROOT|" report/index.html
          sed -i "s|__PROD_HEALTH__|$PROD_HEALTH|" report/index.html
          sed -i "s|__PROD_ROOT__|$PROD_ROOT|" report/index.html
        '''
        archiveArtifacts artifacts: 'report/**', fingerprint: true, onlyIfSuccessful: false
      }
    }
  }

  post {
    always {
      sh '''
        if [ -d infra ]; then
          cd infra
          terraform init -input=false || true
          terraform destroy -auto-approve -var image_name=${IMAGE_NAME} -var tag=${SHORT_SHA} || true
        fi
      '''
    }
  }
}
