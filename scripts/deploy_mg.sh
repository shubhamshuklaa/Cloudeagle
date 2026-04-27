#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="$1"
ENVIRONMENT="$2"
IMAGE_URI="$3"
MIG_NAME="$4"
LOCATION="$5"
SCOPE="$6"

TEMPLATE_NAME="${MIG_NAME}-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)"
STARTUP_SCRIPT="startup-${ENVIRONMENT}.sh"

cat > "${STARTUP_SCRIPT}" <<SCRIPT
#!/bin/bash
set -euxo pipefail

APP_NAME="sync-service"
IMAGE_URI="${IMAGE_URI}"
SECRET_PREFIX="sync-service-${ENVIRONMENT}"

mkdir -p /opt/

MONGO_URI=$(gcloud secrets versions access latest --secret="${SECRET_PREFIX}-mongodb-uri")
API_KEY=$(gcloud secrets versions access latest --secret="${SECRET_PREFIX}-api-key")

cat >/opt/${APP_NAME}.env <<ENVFILE
SPRING_PROFILES_ACTIVE=${ENVIRONMENT}
MONGODB_URI=${MONGO_URI}
EXTERNAL_API_KEY=${API_KEY}
ENVFILE

/usr/bin/docker rm -f ${APP_NAME} || true
/usr/bin/docker pull ${IMAGE_URI}
/usr/bin/docker run -d \
  --name ${APP_NAME} \
  --restart unless-stopped \
  --env-file /opt/${APP_NAME}.env \
  -p 8080:8080 \
  ${IMAGE_URI}
SCRIPT

chmod +x "${STARTUP_SCRIPT}"

gcloud config set project "${PROJECT_ID}" >/dev/null

if [[ "${SCOPE}" == "region" ]]; then
  gcloud compute instance-templates create "${TEMPLATE_NAME}" \
    --region "${LOCATION}" \
    --machine-type e2-standard-4 \
    --network-interface subnet=default,no-address \
    --service-account "sync-service-${ENVIRONMENT}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --scopes cloud-platform \
    --metadata-from-file startup-script="${STARTUP_SCRIPT}" \
    --tags "${APP_NAME}","${ENVIRONMENT}"

  gcloud compute instance-groups managed rolling-action start-update "${MIG_NAME}" \
    --region "${LOCATION}" \
    --version template="${TEMPLATE_NAME}" \
    --max-unavailable 0 \
    --max-surge 1
else
  gcloud compute instance-templates create "${TEMPLATE_NAME}" \
    --machine-type e2-standard-2 \
    --network-interface subnet=default,no-address \
    --service-account "sync-service-${ENVIRONMENT}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --scopes cloud-platform \
    --metadata-from-file startup-script="${STARTUP_SCRIPT}" \
    --tags "${APP_NAME}","${ENVIRONMENT}"

  gcloud compute instance-groups managed rolling-action start-update "${MIG_NAME}" \
    --zone "${LOCATION}" \
    --version template="${TEMPLATE_NAME}" \
    --max-unavailable 0 \
    --max-surge 1
fi

echo "Deployment started using template ${TEMPLATE_NAME}"
