# Deploying the API to Google Cloud Run (demo)

Cloud Run keeps no local disk and scales to zero, so three things differ from a laptop:

| Need | How it is handled |
|---|---|
| Database | PostgreSQL. Use **Cloud SQL** or any hosted Postgres (e.g. Neon/Supabase free tier). SQLite is refused in production. |
| Background worker (reminders, escalation) | Runs **inside the API process** (`MEDTRACK_EMBEDDED_WORKER=true`). Cloud Run must therefore never throttle CPU or scale to zero: the script uses `--no-cpu-throttling --min-instances 1 --max-instances 1`. |
| Schema | `MEDTRACK_AUTO_MIGRATE=true` runs Alembic at start-up (safe with a single instance). |

## Steps
1. Create a Postgres database. Cloud SQL example:
   ```
   gcloud sql instances create meditrack-db --database-version=POSTGRES_16 --tier=db-f1-micro --region=asia-south1
   gcloud sql databases create meditrack --instance=meditrack-db
   gcloud sql users create meditrack --instance=meditrack-db --password='<choose>'
   ```
   Then use `postgresql+psycopg://meditrack:<pw>@/meditrack?host=/cloudsql/<PROJECT>:asia-south1:meditrack-db` as `DATABASE_URL`
   and add `--add-cloudsql-instances <PROJECT>:asia-south1:meditrack-db` to the deploy command in the script.
   (A hosted Postgres URL with `?sslmode=require` is simpler.)
2. `export PROJECT=... REGION=asia-south1 DATABASE_URL=...` and run `./deploy/cloudrun.sh`.
3. Open the printed URL + `/ready`. In the app: **Sign in → Server → paste the URL**.

## Demo mode, honestly
`MEDTRACK_DEMO_MODE=true` creates sample accounts (see `DEMO_GUIDE.md`) with a publicly documented password and
uses **simulated** WhatsApp/phone providers: the API marks those deliveries `simulated: true` and the app says
"Simulated (demo mode) – no real message was sent". For anything real: unset both demo variables, set the
provider credentials (`INTEGRATIONS.md`), create a super admin with the CLI, and keep secrets in Secret Manager
instead of plain env vars.

## Not verified
This deployment path has **not been run** (no GCP project or Docker here). The container entrypoint, the app and
the migrations were verified locally with `uvicorn` against SQLite and the unit tests; Postgres and Cloud Run
behaviour is untested.
