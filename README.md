# Grocery List App

Cross-platform Flutter app (iOS, Android, Web) for shared real-time grocery lists powered by Firebase.

## Features

- **Firebase Auth** — Email/password and Google Sign-In
- **Cloud Firestore** — Real-time sync via snapshot listeners
- **Households** — Shared family groups linked by invite code
- **Roles** — `familyAdmin` and `familyMember`
- **Riverpod** — Reactive state management
- **Carrefour prices** — Read-only price search through Firebase Functions, with the product catalog stored in Firestore

### Carrefour catalog

The scraper runs as a Cloud Run Job in its own Chrome container, using Xvfb to provide the headed browser window that the site currently needs. It scrapes Carrefour and sends product batches to the IAM-private `syncCarrefourCatalog` Function, which also checks the `CARREFOUR_CATALOG_SYNC_TOKEN` secret before writing to the server-only `carrefourProducts` collection. The read API requires a signed-in Firebase user.

The job image and runner are in `cloudrun_scraper/`. After `gcloud auth login` and `gcloud config set project animemusic-e8c09`, create its least-privilege runtime identity:

```bash
gcloud iam service-accounts create carrefour-scraper \
  --project animemusic-e8c09 \
  --display-name "Carrefour catalog scraper"
```

Deploy the sync Function as IAM-private with the catalog token secret:

```bash
gcloud functions deploy syncCarrefourCatalog \
  --gen2 --runtime=nodejs22 --region=europe-west1 \
  --project=animemusic-e8c09 --source=functions \
  --entry-point=syncCarrefourCatalog --trigger-http \
  --no-allow-unauthenticated \
  --service-account=207784872626-compute@developer.gserviceaccount.com \
  --timeout=120s --memory=512Mi \
  --set-secrets=CARREFOUR_CATALOG_SYNC_TOKEN=CARREFOUR_CATALOG_SYNC_TOKEN:latest

gcloud run services add-iam-policy-binding synccarrefourcatalog \
  --project animemusic-e8c09 --region europe-west1 \
  --member serviceAccount:carrefour-scraper@animemusic-e8c09.iam.gserviceaccount.com \
  --role roles/run.invoker

gcloud secrets add-iam-policy-binding CARREFOUR_CATALOG_SYNC_TOKEN \
  --project animemusic-e8c09 \
  --member serviceAccount:carrefour-scraper@animemusic-e8c09.iam.gserviceaccount.com \
  --role roles/secretmanager.secretAccessor
```

Grant the job access to the token and deploy it:

```bash
gcloud run jobs deploy carrefour-catalog-scraper \
  --source cloudrun_scraper \
  --project animemusic-e8c09 \
  --region europe-west1 \
  --service-account carrefour-scraper@animemusic-e8c09.iam.gserviceaccount.com \
  --task-timeout 60m \
  --memory 2Gi \
  --cpu 2 \
  --max-retries 1 \
  --set-env-vars CARREFOUR_SYNC_URL=https://synccarrefourcatalog-2a7u7yjvva-ew.a.run.app \
  --set-secrets CARREFOUR_CATALOG_SYNC_TOKEN=CARREFOUR_CATALOG_SYNC_TOKEN:latest

gcloud run jobs execute carrefour-catalog-scraper \
  --project animemusic-e8c09 --region europe-west1 --wait
```

Schedule a daily run for 4:00 AM Cairo time:

```bash
gcloud run jobs add-iam-policy-binding carrefour-catalog-scraper \
  --project=animemusic-e8c09 --region=europe-west1 \
  --member=serviceAccount:carrefour-scraper@animemusic-e8c09.iam.gserviceaccount.com \
  --role=roles/run.invoker

gcloud scheduler jobs create http carrefour-catalog-daily \
  --project=animemusic-e8c09 --location=europe-west1 \
  --schedule='0 4 * * *' --time-zone='Africa/Cairo' \
  --uri='https://run.googleapis.com/v2/projects/animemusic-e8c09/locations/europe-west1/jobs/carrefour-catalog-scraper:run' \
  --http-method=POST \
  --oauth-service-account-email=carrefour-scraper@animemusic-e8c09.iam.gserviceaccount.com \
  --oauth-token-scope=https://www.googleapis.com/auth/cloud-platform \
  --message-body='{}'
```

Cloud Run's service identity obtains the private Function's Google identity token automatically. The write Function is IAM-private and also checks the sync secret; the app never receives that token. The job has ephemeral local disk, so each run starts with a fresh Chrome profile. If Carrefour requires a manually solved challenge or persistent profile in a later run, use a VM with a persistent Chrome profile instead.

The app reads from `https://carrefourapi-2a7u7yjvva-ew.a.run.app/products` with the signed-in user's Firebase ID token. Set `--dart-define=CARREFOUR_API_BASE_URL=http://127.0.0.1:8000` only when deliberately testing against the local FastAPI server.

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── app.dart                  # MaterialApp + routing
├── firebase_options.dart     # Generated Firebase config
├── constants/
├── models/
├── services/
├── providers/
├── screens/
└── widgets/
```

## Setup

1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.2+).

2. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com).

3. Enable **Authentication** (Email/Password + Google) and **Cloud Firestore**.

4. Install FlutterFire CLI and configure:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

5. Deploy Firestore security rules:
   ```bash
   firebase deploy --only firestore:rules
   ```

6. Install dependencies and run:
   ```bash
   cd grocery_list_app
   flutter pub get
   flutter run -d chrome    # Web
   flutter run              # Connected device/emulator
   ```

## Firestore Data Model

```
users/{userId}
  email, displayName, role, householdId?, createdAt, updatedAt

households/{householdId}
  name, inviteCode, createdBy, createdAt, updatedAt
  └── items/{itemId}
        name, quantity, isChecked, addedBy, createdAt, updatedAt

inviteCodes/{code}
  householdId, createdAt
```

## User Roles

| Role            | Firestore value  | Permissions                          |
|-----------------|------------------|--------------------------------------|
| Family Admin    | `familyAdmin`    | Create household, rename, delete     |
| Family Member   | `familyMember`   | View/add/edit/check off list items   |

All household members can CRUD grocery items in real time.

## Real-Time Sync

Grocery items use Firestore `.snapshots()` streams. Any write on one device propagates instantly to all other active sessions (iOS, Android, Web) through the `groceryListProvider` Riverpod stream.

## Local Carrefour Price Lookup

The price button on each grocery item reads results from the hosted Firebase API. For simulator development against the local FastAPI server:

1. Start `carrefour_api.py` in the folder containing both API and scraper files:
   ```bash
   uvicorn carrefour_api:app --host 127.0.0.1 --port 8000
   ```
2. Open `http://127.0.0.1:8000/docs` and call `POST /refresh` once to populate its SQLite catalog.
3. Run the app in the iOS simulator. Debug builds use `http://127.0.0.1:8000` by default; Android emulators use `http://10.0.2.2:8000`.

For a different API address, pass `--dart-define=CARREFOUR_API_BASE_URL=https://your-api-host` to `flutter run` or the release build. Published builds need a hosted HTTPS API; the local API is only for development.
