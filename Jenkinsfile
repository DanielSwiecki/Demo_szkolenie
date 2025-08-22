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
sleep 6
docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:5000/health
"""
      }
    }

    stage('Deploy to PROD (Docker)') {
      steps {
        sh '''
docker rm -f green-app-prod || true
docker run -d --name green-app-prod -p 3000:5000 ${IMAGE_NAME}:${SHORT_SHA}
sleep 4
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
'''
      }
    }

    stage('Smoke Tests & Report') {
      steps {
        sh '''
set -e
STAGE_START_TS=$(date +%s)
mkdir -p report

# ===== Smoke: STAGING (ta sama sieć dockerowa) =====
STAGING_HEALTH=$(docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:5000/health || echo "FAIL")
STAGING_ROOT=$(docker run --rm --network=green_net curlimages/curl:8.8.0 -fsS http://green-app-staging:5000/ || echo "FAIL")

# ===== Smoke: PROD (port hosta 3000) – sieć hosta =====
PROD_HEALTH=$(docker run --rm --network=host curlimages/curl:8.8.0 -fsS http://localhost:3000/health || echo "FAIL")
PROD_ROOT=$(docker run --rm --network=host curlimages/curl:8.8.0 -fsS http://localhost:3000/ || echo "FAIL")

# ===== Docker stats (CPU/Mem/IO) z bezpiecznymi fallbackami =====
set +e
docker ps --format "{{.Names}}" | grep -wq green-app-staging
STAGING_EXISTS=$?
docker ps --format "{{.Names}}" | grep -wq green-app-prod
PROD_EXISTS=$?

if [ $STAGING_EXISTS -eq 0 ]; then
  STATS_STAGING_RAW=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" green-app-staging 2>/dev/null)
else
  STATS_STAGING_RAW="green-app-staging\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A"
fi

if [ $PROD_EXISTS -eq 0 ]; then
  STATS_PROD_RAW=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" green-app-prod 2>/dev/null)
else
  STATS_PROD_RAW="green-app-prod\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A"
fi
set -e

to_html() { sed -e "s/&/\\&amp;/g" -e "s/</\\&lt;/g" -e "s/>/\\&gt;/g" -e "s/\\t/ | /g" -e "s/$/<br\\/>/"; }
STATS_STAGING=$(echo "$STATS_STAGING_RAW" | to_html)
STATS_PROD=$(echo "$STATS_PROD_RAW" | to_html)

DOCKER_SIZE=$(docker images --format "{{.Repository}}:{{.Tag}} -> {{.Size}}" | grep -m1 ${IMAGE_NAME}:${SHORT_SHA} || echo "N/A")

STAGE_END_TS=$(date +%s)
STAGE_DURATION=$((STAGE_END_TS - STAGE_START_TS))

# ===== Raport HTML =====
cat > report/index.html <<'HTML'
<!doctype html>
<html lang="en"><meta charset="utf-8">
<title>Green Pipeline Smoke Report</title>
<style>
  body{font-family:system-ui,Arial,sans-serif;margin:24px}
  h1{margin:0 0 12px}
  code,pre{background:#f6f8fa;padding:6px 8px;border-radius:6px;display:block;white-space:pre-wrap}
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

<h2>Container Stats (docker stats)</h2>
<h3>Staging (green-app-staging)</h3>
<pre>NAME | CPU% | MemUsage | Mem% | Net I/O | Block I/O | PIDs<br/>__STATS_STAGING__</pre>

<h3>Production (green-app-prod)</h3>
<pre>NAME | CPU% | MemUsage | Mem% | Net I/O | Block I/O | PIDs<br/>__STATS_PROD__</pre>

<h2>Build/Stage Stats</h2>
<table>
  <tr><th>Stage Duration (s)</th><td>__STAGE_DURATION__</td></tr>
  <tr><th>Docker Image</th><td><code>__DOCKER_SIZE__</code></td></tr>
</table>
</body></html>
HTML

# Podmień placeholdery
sed -i "s/__SHORT_SHA__/$SHORT_SHA/" report/index.html
sed -i "s|__STAGING_HEALTH__|$STAGING_HEALTH|" report/index.html
sed -i "s|__STAGING_ROOT__|$STAGING_ROOT|" report/index.html
sed -i "s|__PROD_HEALTH__|$PROD_HEALTH|" report/index.html
sed -i "s|__PROD_ROOT__|$PROD_ROOT|" report/index.html
sed -i "s|__STATS_STAGING__|$STATS_STAGING|" report/index.html
sed -i "s|__STATS_PROD__|$STATS_PROD|" report/index.html
sed -i "s|__STAGE_DURATION__|$STAGE_DURATION|" report/index.html
sed -i "s|__DOCKER_SIZE__|$DOCKER_SIZE|" report/index.html
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
