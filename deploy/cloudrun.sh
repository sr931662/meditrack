#!/usr/bin/env bash
# Deploy the MediTrack API to Google Cloud Run in DEMO mode (sample data, SIMULATED alerts).
# Prereqs: gcloud logged in, a project with billing, and a PostgreSQL URL (Cloud SQL or any hosted Postgres).
#   export PROJECT=my-project REGION=asia-south1
#   export DATABASE_URL='postgresql+psycopg://USER:PASSWORD@HOST:5432/DBNAME'   # see docs/CLOUD_RUN.md for Cloud SQL
#   ./deploy/cloudrun.sh
set -euo pipefail
: "${PROJECT:?set PROJECT}" "${REGION:=asia-south1}" "${DATABASE_URL:?set DATABASE_URL}"
SERVICE=${SERVICE:-meditrack-api}
JWT_SECRET=${JWT_SECRET:-$(python3 -c 'import secrets;print(secrets.token_urlsafe(48))')}

gcloud services enable run.googleapis.com cloudbuild.googleapis.com --project "$PROJECT"

# --no-cpu-throttling + min/max 1: the reminder worker runs inside the API process and must keep ticking.
gcloud run deploy "$SERVICE" --source server --project "$PROJECT" --region "$REGION" \
  --allow-unauthenticated --no-cpu-throttling --min-instances 1 --max-instances 1 --memory 512Mi \
  --set-env-vars "MEDTRACK_ENV=production,MEDTRACK_DATABASE_URL=${DATABASE_URL},MEDTRACK_JWT_SECRET=${JWT_SECRET},MEDTRACK_AUTO_MIGRATE=true,MEDTRACK_EMBEDDED_WORKER=true,MEDTRACK_DEMO_MODE=true,MEDTRACK_PROVIDER_MODE=demo"

URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format 'value(status.url)')
echo "Deployed: $URL"
curl -fsS "$URL/ready" && echo
echo "In the app: Sign-in screen -> 'Server' -> paste $URL"
