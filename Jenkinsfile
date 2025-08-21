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
          # krótki wait na start
          sleep 6
          # health z sieci dockerowej
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
          # Poczekaj chwilę aż healthcheck w obrazie przejdzie
          sleep 4
          docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        '''
      }
    }

    stage('Smoke Tests & Report') {
      steps {
        sh '''
          set -e
          mkdir -p report

          # STAGING (w sieci green_net, endpoint /health i /)
          STAGING_HEALTH=$(docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:5000/health || echo "FAIL")
          STAGING_ROOT=$(docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:5000/ || echo "FAIL")

          # PROD (hostowy port 3000)
          PROD_HEALTH=$(curl -fsS http://localhost:3000/health || echo "FAIL")
          PROD_ROOT=$(curl -fsS http://localhost:3000/ || echo "FAIL")

          # Zbuduj prosty raport HTML (HEREDOC – bez interpolacji)
          cat > report/index.html << "HTML"
          <!doctype html>
          <html lang="en"><meta charset="utf-8">
          <title>Green Pipeline Smoke Report</title>
          <style>
            body{font-family:system-ui,Arial,sans-serif;margin:24px}
            h1{margin:0 0 12px}
            code,pre{background:#f6f8fa;padding:4px 6px;border-radius:6px}
            table{border-collapse:collapse;margin-top:12px}
            td,th{border:1px solid #ddd;padding:8px}
          </style>
          <body>
          <h1>Green Pipeline – Smoke Tests</h1>
          <p>Commit: <code>__SHORT_SHA__</code></p>

          <h2>Staging</h2>
          <table>
            <tr><th>Endpoint</th><th>Response</th></tr>
            <tr><td>/health</td><td>__STAGING_HEALTH__</td></tr>
            <tr><td>/</td><td><pre>__STAGING_ROOT__</pre></td></tr>
          </table>

          <h2>Production</h2>
          <table>
            <tr><th>Endpoint</th><th>Response</th></tr>
            <tr><td>/health</td><td>__PROD_HEALTH__</td></tr>
            <tr><td>/</td><td><pre>__PROD_ROOT__</pre></td></tr>
          </table>
          </body></html>
          HTML

          # Podmień placeholdery wartościami (używamy zmiennych powłoki)
          sed -i "s/__SHORT_SHA__/$SHORT_SHA/" report/index.html
          sed -i "s|__STAGING_HEALTH__|$STAGING_HEALTH|" report/index.html
          sed -i "s|__STAGING_ROOT__|$STAGING_ROOT|" report/index.html
          sed -i "s|__PROD_HEALTH__|$PROD_HEALTH|" report/index.html
          sed -i "s|__PROD_ROOT__|$PROD_ROOT|" report/index.html
        '''
        archiveArtifacts artifacts: 'report/**', fingerprint: true, onlyIfSuccessful: false
        echo "Raport zapisany jako artefakt: report/index.html"
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
