pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    APP_NAME        = 'sync-service'
    REGION          = 'asia-south1'
    PROJECT_ID_QA   = 'your-qa-project-id'
    PROJECT_ID_STG  = 'your-staging-project-id'
    PROJECT_ID_PROD = 'your-prod-project-id'
    ARTIFACT_REPO   = 'app-images'
    IMAGE_NAME      = 'sync-service'
    QA_MIG          = 'sync-service-qa-mig'
    STG_MIG         = 'sync-service-staging-mig'
    PROD_MIG        = 'sync-service-prod-mig'
    QA_ZONE         = 'asia-south1-a'
    STG_ZONE        = 'asia-south1-b'
    PROD_REGION     = 'asia-south1'
    HEALTH_URL_QA   = 'https://qa.example.com/actuator/health'
    HEALTH_URL_STG  = 'https://staging.example.com/actuator/health'
    HEALTH_URL_PROD = 'https://api.example.com/actuator/health'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.VERSION = env.TAG_NAME ? env.TAG_NAME : "${env.BRANCH_NAME}-${env.BUILD_NUMBER}-${env.GIT_SHA}"
          env.IMAGE_URI_QA   = "${REGION}-docker.pkg.dev/${PROJECT_ID_QA}/${ARTIFACT_REPO}/${IMAGE_NAME}:${VERSION}"
          env.IMAGE_URI_STG  = "${REGION}-docker.pkg.dev/${PROJECT_ID_STG}/${ARTIFACT_REPO}/${IMAGE_NAME}:${VERSION}"
          env.IMAGE_URI_PROD = "${REGION}-docker.pkg.dev/${PROJECT_ID_PROD}/${ARTIFACT_REPO}/${IMAGE_NAME}:${VERSION}"
        }
      }
    }

    stage('Set Target Environment') {
      steps {
        script {
          env.DEPLOY_ENV = ''
          env.DEPLOY_PROJECT = ''
          env.DEPLOY_MIG = ''
          env.DEPLOY_LOCATION = ''
          env.DEPLOY_SCOPE = ''
          env.DEPLOY_HEALTH_URL = ''
          env.DEPLOY_IMAGE_URI = ''

          if (env.CHANGE_ID) {
            echo 'Pull request build detected. Validation only.'
          } else if (env.BRANCH_NAME == 'develop') {
            env.DEPLOY_ENV = 'qa'
            env.DEPLOY_PROJECT = env.PROJECT_ID_QA
            env.DEPLOY_MIG = env.QA_MIG
            env.DEPLOY_LOCATION = env.QA_ZONE
            env.DEPLOY_SCOPE = 'zone'
            env.DEPLOY_HEALTH_URL = env.HEALTH_URL_QA
            env.DEPLOY_IMAGE_URI = env.IMAGE_URI_QA
          } else if (env.BRANCH_NAME?.startsWith('release/')) {
            env.DEPLOY_ENV = 'staging'
            env.DEPLOY_PROJECT = env.PROJECT_ID_STG
            env.DEPLOY_MIG = env.STG_MIG
            env.DEPLOY_LOCATION = env.STG_ZONE
            env.DEPLOY_SCOPE = 'zone'
            env.DEPLOY_HEALTH_URL = env.HEALTH_URL_STG
            env.DEPLOY_IMAGE_URI = env.IMAGE_URI_STG
          } else if (env.TAG_NAME ==~ /^v\d+\.\d+\.\d+(-rc\.\d+)?$/) {
            env.DEPLOY_ENV = 'prod'
            env.DEPLOY_PROJECT = env.PROJECT_ID_PROD
            env.DEPLOY_MIG = env.PROD_MIG
            env.DEPLOY_LOCATION = env.PROD_REGION
            env.DEPLOY_SCOPE = 'region'
            env.DEPLOY_HEALTH_URL = env.HEALTH_URL_PROD
            env.DEPLOY_IMAGE_URI = env.IMAGE_URI_PROD
          } else {
            echo 'No deployment target for this branch.'
          }

          echo "Target environment: ${env.DEPLOY_ENV}"
        }
      }
    }

    stage('Build') {
      steps {
        sh './mvnw -B clean package -DskipTests'
      }
    }

    stage('Unit Tests') {
      steps {
        sh './mvnw -B test'
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
        }
      }
    }

    stage('Static Analysis') {
      steps {
        sh './mvnw -B spotbugs:check || true'
      }
    }

    stage('Integration Tests') {
      steps {
        sh './mvnw -B verify -DskipUnitTests=true || true'
      }
    }

    stage('Build Image') {
      steps {
        sh '''
          docker build \
            -t ${APP_NAME}:${VERSION} \
            .
        '''
      }
    }

    stage('Push Image') {
      when {
        expression { return !env.CHANGE_ID && env.DEPLOY_ENV?.trim() }
      }
      steps {
        sh '''
          gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
          docker tag ${APP_NAME}:${VERSION} ${DEPLOY_IMAGE_URI}
          docker push ${DEPLOY_IMAGE_URI}
        '''
      }
    }

    stage('Production Approval') {
      when {
        expression { return env.DEPLOY_ENV == 'prod' }
      }
      steps {
        input message: "Deploy ${APP_NAME} ${VERSION} to production?", ok: 'Deploy', submitter: 'release-managers,devops-leads'
      }
    }

    stage('Deploy') {
      when {
        expression { return !env.CHANGE_ID && env.DEPLOY_ENV?.trim() }
      }
      steps {
        sh '''
          chmod +x scripts/deploy_mig.sh
          ./scripts/deploy_mig.sh \
            ${DEPLOY_PROJECT} \
            ${DEPLOY_ENV} \
            ${DEPLOY_IMAGE_URI} \
            ${DEPLOY_MIG} \
            ${DEPLOY_LOCATION} \
            ${DEPLOY_SCOPE}
        '''
      }
    }

    stage('Smoke Test') {
      when {
        expression { return !env.CHANGE_ID && env.DEPLOY_ENV?.trim() }
      }
      steps {
        sh '''
          echo "Running smoke test against ${DEPLOY_HEALTH_URL}"
          for i in $(seq 1 20); do
            if curl -fsS ${DEPLOY_HEALTH_URL}; then
              echo 'Health check passed.'
              exit 0
            fi
            echo 'Health check not ready yet. Retrying...'
            sleep 15
          done
          echo 'Smoke test failed.'
          exit 1
        '''
      }
    }
  }

  post {
    failure {
      script {
        if (!env.CHANGE_ID && env.DEPLOY_ENV?.trim()) {
          sh '''
            chmod +x scripts/rollback_mig.sh
            ./scripts/rollback_mig.sh \
              ${DEPLOY_PROJECT} \
              ${DEPLOY_MIG} \
              ${DEPLOY_LOCATION} \
              ${DEPLOY_SCOPE}
          '''
        }
      }
    }
    success {
      echo "Build completed successfully for ${env.DEPLOY_ENV ?: 'validation-only'}"
    }
  }
}
