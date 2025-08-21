pipeline {
  agent any
  options { timestamps() }
  environment {
    IMAGE_NAME = "green-app"
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.SHORT_SHA = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          env.ACTUAL_BRANCH = env.BRANCH_NAME ?: sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
          echo "Branch: ${env.ACTUAL_BRANCH}, Commit: ${env.SHORT_SHA}"
        }
      }
    }

      stage('Unit Tests (Node via Docker)') {
    steps {
      sh '''
        docker run --rm -v "$PWD":/workspace -w /workspace node:20-alpine sh -lc "node -v && (npm ci || npm install) && npm test"
      '''
    }
  }


    stage('Build Docker Image') {
      steps {
        sh '''
          docker build -t ${IMAGE_NAME}:${SHORT_SHA} .
          docker tag ${IMAGE_NAME}:${SHORT_SHA} ${IMAGE_NAME}:latest
          docker images | head -n 10
        '''
      }
    }

   stage('Integration (staging via Terraform)') {
  when { branch 'main' }
  steps {
    sh '''
      cd infra
      terraform init -input=false
      terraform apply -auto-approve -var image_name=${IMAGE_NAME} -var tag=${SHORT_SHA}

      # krótki wait na start
      sleep 3

      # Sprawdzamy /health "od środka" tej samej sieci dockerowej
      docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:3000/health
    '''
  }
}


    stage('Deploy to PROD (Docker)') {
      when { branch 'main' }
      steps {
        sh '''
          docker rm -f green-app-prod || true
          docker run -d --name green-app-prod -p 3000:3000 ${IMAGE_NAME}:${SHORT_SHA}
        '''
      }
    }
  }

  post {
    always {
      sh '''
        cd infra || exit 0
        terraform destroy -auto-approve -var image_name=${IMAGE_NAME} -var tag=${SHORT_SHA} || true
      '''
    }
  }
}
