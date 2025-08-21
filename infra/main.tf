pipeline {
  agent any
  options { timestamps() }

  environment { IMAGE_NAME = "green-app" }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.SHORT_SHA = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          env.ACTUAL_BRANCH = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
          echo "Branch: ${env.ACTUAL_BRANCH}, Commit: ${env.SHORT_SHA}"
        }
      }
    }

    stage('Workspace sanity check') {
      steps {
        sh '''
          echo "== WORKSPACE ==" && pwd && ls -la
          echo "== infra ==" && ls -la infra || true
        '''
      }
    }

    stage('Unit Tests (Python via Docker) - fail-open') {
      steps {
        script {
          // prościutki test: Python działa; jak się wywali -> UNSTABLE, ale pipeline idzie dalej
          catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
            sh """
              docker run --rm -v "${WORKSPACE}":/workspace -w /workspace python:3.11-alpine \
                /bin/sh -lc 'python --version && python -c "print(\\\"unit ok\\\")"'
            """
          }
        }
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
      steps {
        sh """
          set -e
          cd infra
          terraform init -input=false
          terraform apply -auto-approve -var image_name=${IMAGE_NAME} -var tag=${SHORT_SHA}
          sleep 5
          docker run --rm --network=green_net curlimages/curl:8.8.0 \
            -fsS http://green-app-staging:5000/health
        """
      }
    }

    stage('Deploy to PROD (Docker)') {
      steps {
        sh '''
          docker rm -f green-app-prod || true
          docker run -d --name green-app-prod -p 3000:5000 ${IMAGE_NAME}:${SHORT_SHA}
          docker ps
        '''
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
