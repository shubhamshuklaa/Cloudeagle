#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="$1"
MIG_NAME="$2"
LOCATION="$3"
SCOPE="$4"

gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Finding previous instance template for rollback..."

if [[ "${SCOPE}" == "region" ]]; then
  CURRENT=$(gcloud compute instance-groups managed describe "${MIG_NAME}" --region "${LOCATION}" --format='value(versions[0].instanceTemplate)')
  PREVIOUS=$(gcloud compute instance-templates list --sort-by=~creationTimestamp --filter="name~^${MIG_NAME}" --format='value(name)' | sed -n '2p')

  if [[ -z "${PREVIOUS}" ]]; then
    echo "No previous template found for rollback."
    exit 1
  fi

  gcloud compute instance-groups managed rolling-action start-update "${MIG_NAME}" \
    --region "${LOCATION}" \
    --version template="${PREVIOUS}" \
    --max-unavailable 0 \
    --max-surge 1
else
  CURRENT=$(gcloud compute instance-groups managed describe "${MIG_NAME}" --zone "${LOCATION}" --format='value(versions[0].instanceTemplate)')
  PREVIOUS=$(gcloud compute instance-templates list --sort-by=~creationTimestamp --filter="name~^${MIG_NAME}" --format='value(name)' | sed -n '2p')

  if [[ -z "${PREVIOUS}" ]]; then
    echo "No previous template found for rollback."
    exit 1
  fi

  gcloud compute instance-groups managed rolling-action start-update "${MIG_NAME}" \
    --zone "${LOCATION}" \
    --version template="${PREVIOUS}" \
    --max-unavailable 0 \
    --max-surge 1
fi

echo "Rollback started. Previous template: ${PREVIOUS}. Current template was: ${CURRENT}"
