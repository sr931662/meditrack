# Build, Test & Deployment

## Backend (`server/`)

```bash
cd server
python -m venv .venv && .venv/Scripts/activate      # Linux/macOS: source .venv/bin/activate
pip install -r requirements-dev.txt
pytest                      # 81 tests, SQLite in-memory
ruff check . && ruff format --check .
```

### Run locally against PostgreSQL (Docker, **untested in this repo's environment**)

```bash
docker compose up --build   # db, migrate, api (:8000), worker
docker compose run --rm api python -m app.cli create-super-admin --email you@x.com --name "You"
```

### Production checklist

1. Environment (see `server/.env.example`): `MEDTRACK_ENV=production`, `MEDTRACK_DATABASE_URL` (Postgres),
   `MEDTRACK_JWT_SECRET` (≥32 random chars), `MEDTRACK_PROVIDER_MODE=live` + provider credentials.
   The app **refuses to start** in production with the default secret, mock providers or SQLite.
2. Run migrations before each rollout: `alembic upgrade head` (one-shot job). Downgrade is tested for the schema.
3. Run **two** processes from the same image: API (`uvicorn app.main:app`) and worker (`python -m app.worker`);
   scale the worker freely (jobs are claimed with `SKIP LOCKED`).
4. Terminate TLS at a proxy/load balancer; set `--proxy-headers`. Add a gateway rate limiter (the built-in one is per-process).
5. Create the first admin once with the CLI above; there is no default account.
6. Health: `GET /health` (liveness), `GET /ready` (DB reachable). OpenAPI at `/docs` (disabled in production).
7. **Backups**: daily `pg_dump` (or managed PITR), encrypted, restored regularly into a scratch DB to prove it works;
   keep audit_logs. Not automated in this repo.
8. **Retention/deletion**: no automated job yet. Define a policy per jurisdiction before launch.
9. Monitoring: hook `FlutterError.onError` and an ASGI exception middleware to Sentry or similar (not wired).

### Compliance
This repository makes **no** HIPAA, DPDP, GDPR or DSCI claim. Determine the obligations of the target
jurisdiction (consent, data residency, breach notification, processor agreements with WhatsApp/Twilio) and
have them reviewed before processing real patient data.

## Client (`client/`)

```bash
cd client
flutter pub get
flutter analyze && flutter test        # 53 tests
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1      # emulator → host
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://api.example.com/api/v1 --dart-define=APP_ENV=production
```

* Application id `com.mavicode.meditrack` (change before publishing).
* **Release signing**: create a keystore and `client/android/key.properties` (git-ignored):
  ```
  storeFile=../upload.jks
  storePassword=…
  keyAlias=upload
  keyPassword=…
  ```
  Without it the release build is signed with the debug key and prints a Gradle warning; do not distribute it.
* Release builds are HTTPS-only (`usesCleartextTraffic=false`); the debug manifest allows `http://10.0.2.2`.

### Gradle toolchain note
On the machine used for development, Gradle 9 could not be downloaded, so the project is pinned to
**Gradle 8.14, AGP 8.13.1, Kotlin 2.2.20** (see `android/gradle/wrapper`, `android/settings.gradle.kts`), plus
`desugar_jdk_libs` (required by `flutter_local_notifications`). Builds were run with `GRADLE_USER_HOME=D:\gradle-home`.

### Verified builds
Debug and release APKs were built successfully (see `IMPLEMENTATION_STATUS.md`). They have **not** been
installed on a device.

## CI
`.github/workflows/ci.yml` runs ruff + pytest for the server and analyze + test + debug build for the client.
It has not been executed on GitHub from this environment.
