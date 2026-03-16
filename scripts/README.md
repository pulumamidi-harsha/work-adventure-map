# 📜 Scripts — WorkAdventure Map Management

This directory contains scripts for building, deploying, and cleaning up WorkAdventure maps across all environments.

---

## 📑 Table of Contents

- [Prerequisites](#-prerequisites)
- [Environment URLs](#-environment-urls)
- [deploy-maps.sh — Build & Deploy Maps](#-deploy-mapssh--build--deploy-maps)
- [cleanup-maps.sh — Delete All Maps](#-cleanup-mapssh--delete-all-maps)
- [Delete a Single Map](#-delete-a-single-map)
- [List All Maps](#-list-all-maps)
- [GitHub Actions CI/CD](#-github-actions-cicd)
- [Pre-commit / Pre-push Hooks](#-pre-commit--pre-push-hooks)
- [API Reference](#-api-reference)
- [Troubleshooting](#-troubleshooting)

---

## 🔧 Prerequisites

| Tool        | Version  | Purpose                          |
|-------------|----------|----------------------------------|
| Node.js     | ≥ 20     | Build maps (`npm run build`)     |
| npm         | ≥ 10     | Package manager                  |
| curl        | any      | API calls to map-storage         |
| jq          | any      | Parse JSON responses             |
| python3     | ≥ 3.6    | URL-encode map names             |
| zip / unzip | any      | Create/extract zip artifacts     |
| git         | any      | Version control + hooks          |

Install dependencies first:

```bash
cd /path/to/work-adventure-map
npm install
```

---

## 🌐 Environment URLs

| Environment | App Domain                           | Map Storage URL                                                        |
|-------------|--------------------------------------|------------------------------------------------------------------------|
| **dev**     | `dev.dso-os.int.bayer.com`           | `https://virtual-office.dev.dso-os.int.bayer.com/map-storage`          |
| **staging** | `staging.dso-os.int.bayer.com`       | `https://virtual-office.staging.dso-os.int.bayer.com/map-storage`      |
| **prod**    | `dso-os.int.bayer.com`               | `https://virtual-office.dso-os.int.bayer.com/map-storage`              |

**Alternative domains** (legacy / workadventure prefix):

| Environment | Map Storage URL                                                       |
|-------------|-----------------------------------------------------------------------|
| **dev**     | `https://workadventure.dev.dso-os.int.bayer.com/map-storage`         |
| **staging** | `https://workadventure.staging.dso-os.int.bayer.com/map-storage`     |
| **prod**    | `https://workadventure.dso-os.int.bayer.com/map-storage`             |

### 🔑 Authentication

All map-storage endpoints use **HTTP Basic Auth** (username + password).
Credentials are the same ones used to log in to the Map Storage UI.

---

## 🚀 deploy-maps.sh — Build & Deploy Maps

**Purpose:** Full end-to-end pipeline — replaces domains in `.tmj` files, builds the maps, creates a zip, cleans up existing maps, and uploads the new ones.

### Interactive Mode (prompts for everything)

```bash
./scripts/deploy-maps.sh
```

You will be asked to:
1. Select the target environment (dev / staging / prod)
2. Enter username and password

### Non-Interactive Mode

```bash
ENVIRONMENT=staging \
MAPSTORAGE_USER=admin \
MAPSTORAGE_PASSWORD='your-password' \
./scripts/deploy-maps.sh
```

### Build Only (no upload)

```bash
ENVIRONMENT=dev SKIP_UPLOAD=true ./scripts/deploy-maps.sh
```

This creates a zip artifact in `artifacts/` that you can manually upload via the Map Storage UI.

### Skip Cleanup (keep existing maps)

```bash
ENVIRONMENT=staging \
MAPSTORAGE_USER=admin \
MAPSTORAGE_PASSWORD='your-password' \
SKIP_CLEANUP=true \
./scripts/deploy-maps.sh
```

### Skip Build (re-upload existing dist/)

```bash
ENVIRONMENT=staging \
MAPSTORAGE_USER=admin \
MAPSTORAGE_PASSWORD='your-password' \
SKIP_BUILD=true \
./scripts/deploy-maps.sh
```

### Environment Variables

| Variable              | Required | Default | Description                                      |
|-----------------------|----------|---------|--------------------------------------------------|
| `ENVIRONMENT`         | No       | prompt  | `dev` / `staging` / `prod`                       |
| `MAPSTORAGE_USER`     | No       | prompt  | Username for basic auth                          |
| `MAPSTORAGE_PASSWORD` | No       | prompt  | Password for basic auth                          |
| `MAP_STORAGE_URL`     | No       | auto    | Override the auto-detected map-storage URL       |
| `SKIP_UPLOAD`         | No       | `false` | `true` = build only, don't upload                |
| `SKIP_CLEANUP`        | No       | `false` | `true` = don't delete existing maps before upload|
| `SKIP_BUILD`          | No       | `false` | `true` = skip build, use existing `dist/`        |

### What It Does (Step by Step)

1. **Replace domains** — Swaps `staging.dso-os.int.bayer.com` in `.tmj` files with the target environment's domain
2. **Install dependencies** — `npm ci`
3. **Build maps** — `npm run build` (TypeScript compile + Vite tileset optimisation)
4. **Create zip** — Zips `dist/` into `artifacts/maps-{env}-{timestamp}.zip`
5. **Revert domains** — Restores source `.tmj` files to the canonical staging domain
6. **Cleanup** — Deletes all existing maps from the target map-storage
7. **Upload** — Uploads the zip via `POST /map-storage/upload`
8. **Verify** — Confirms the uploaded map count

---

## 🗑️ cleanup-maps.sh — Delete All Maps

**Purpose:** Delete **ALL** maps from a map-storage environment. Useful when you want a clean slate before uploading new maps.

### Interactive Mode

```bash
./scripts/cleanup-maps.sh
```

### Non-Interactive Mode

```bash
ENVIRONMENT=dev \
MAPSTORAGE_USER=admin \
MAPSTORAGE_PASSWORD='your-password' \
./scripts/cleanup-maps.sh
```

### Environment Variables

| Variable              | Required | Default | Description                                |
|-----------------------|----------|---------|--------------------------------------------|
| `ENVIRONMENT`         | No       | prompt  | `dev` / `staging` / `prod`                 |
| `MAPSTORAGE_USER`     | No       | prompt  | Username for basic auth                    |
| `MAPSTORAGE_PASSWORD` | No       | prompt  | Password for basic auth                    |
| `MAP_STORAGE_URL`     | No       | auto    | Override the auto-detected map-storage URL |

### How It Handles Special Characters

Maps with spaces or parentheses in their paths (e.g. `work_adventure_map 2 (1)/lobby.wam`) cannot be deleted via HTTP DELETE due to a URL encoding bug in the map-storage server. The script automatically detects these and falls back to uploading an empty zip to wipe all remaining maps.

---

## 🎯 Delete a Single Map

To delete a **specific** map from an environment, use `curl` directly:

### Syntax

```bash
curl -s -u "USERNAME:PASSWORD" \
  -X DELETE \
  "MAP_STORAGE_URL/MAP_NAME.wam"
```

### Examples

**Delete `lobby.wam` from staging:**

```bash
curl -s -u "admin:your-password" \
  -X DELETE \
  "https://virtual-office.staging.dso-os.int.bayer.com/map-storage/lobby.wam"
```

**Delete `Finance-Platform.wam` from dev:**

```bash
curl -s -u "admin:your-password" \
  -X DELETE \
  "https://virtual-office.dev.dso-os.int.bayer.com/map-storage/Finance-Platform.wam"
```

**Delete `lobby.wam` from prod:**

```bash
curl -s -u "admin:your-password" \
  -X DELETE \
  "https://virtual-office.dso-os.int.bayer.com/map-storage/lobby.wam"
```

**Delete with verbose output (see HTTP status):**

```bash
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  -u "admin:your-password" \
  -X DELETE \
  "https://virtual-office.staging.dso-os.int.bayer.com/map-storage/lobby.wam"
```

> **Expected response:** HTTP `200` or `204` on success.

> ⚠️ **Note:** Map names with spaces or parentheses (e.g. `work_adventure_map 2 (1)/lobby.wam`) **cannot** be deleted individually via HTTP due to a server-side bug. Use `cleanup-maps.sh` instead — it handles these automatically.

---

## 📋 List All Maps

To see all maps currently stored in an environment:

```bash
curl -s -u "admin:your-password" \
  "https://virtual-office.staging.dso-os.int.bayer.com/map-storage/maps" | jq .
```

### Pretty-print just the map names

```bash
curl -s -u "admin:your-password" \
  "https://virtual-office.staging.dso-os.int.bayer.com/map-storage/maps" \
  | jq -r '.maps | keys[]'
```

### Count maps

```bash
curl -s -u "admin:your-password" \
  "https://virtual-office.staging.dso-os.int.bayer.com/map-storage/maps" \
  | jq '.maps | length'
```

---

## 🤖 GitHub Actions CI/CD

The workflow (`.github/workflows/build-maps.yml`) automatically builds map artifacts for all environments on push to `main`/`master`.

### How It Works

Since all environments run on **private subnets** (internal ALB), GitHub Actions runners **cannot** reach map-storage directly. The workflow:

1. Replaces domains in `.tmj` files for each environment
2. Runs `npm run build`
3. **Zips** `dist/` into `maps-{env}.zip`
4. Uploads the zip as a GitHub Actions artifact (30-day retention)

### Download & Deploy Artifacts

1. Go to **Actions** tab → select the workflow run
2. Download the artifact zip (e.g. `maps-staging-42`)
3. The downloaded file contains `maps-staging.zip` — ready to upload
4. Upload to map-storage via:
   - **Map Storage UI:** Open `https://virtual-office.staging.dso-os.int.bayer.com/map-storage/ui` and drag-and-drop the zip
   - **Script:** `SKIP_BUILD=true ./scripts/deploy-maps.sh`

### Manual Trigger

Go to **Actions** → **Build Map Artifacts** → **Run workflow** → select `dev`, `staging`, `prod`, or `all`.

---

## 🔒 Pre-commit / Pre-push Hooks

This repo uses [Husky](https://typicode.github.io/husky/) to run build checks before commits and pushes.

### What They Do

| Hook         | What it runs     | Effect                                   |
|--------------|------------------|------------------------------------------|
| `pre-commit` | `npm run build`  | ❌ Blocks commit if build fails          |
| `pre-push`   | `npm run build`  | ❌ Blocks push if build fails            |

### Setup (automatic)

Hooks are installed automatically when you run `npm install` (via the `prepare` script in `package.json`).

### Bypass Hooks (emergency only)

```bash
# Skip pre-commit hook
git commit --no-verify -m "your message"

# Skip pre-push hook
git push --no-verify
```

> ⚠️ **Use `--no-verify` only in emergencies.** The hooks exist to prevent broken maps from being pushed.

---

## 📡 API Reference

The map-storage exposes these endpoints (all require Basic Auth):

| Method   | Endpoint                    | Description                        | Response           |
|----------|-----------------------------|------------------------------------|--------------------|
| `GET`    | `/map-storage/maps`         | List all stored maps               | JSON with map keys |
| `DELETE` | `/map-storage/{name}.wam`   | Delete a single map                | `200` or `204`     |
| `POST`   | `/map-storage/upload`       | Upload a zip of maps               | `200` or `201`     |
| `GET`    | `/map-storage/ui`           | Map Storage web UI                 | HTML page          |
| `GET`    | `/map-storage/ui/maps`      | Map Storage UI — maps list         | HTML page          |

### Upload Example

```bash
curl -s -u "admin:your-password" \
  -X POST \
  -F "file=@maps-staging.zip" \
  "https://virtual-office.staging.dso-os.int.bayer.com/map-storage/upload"
```

---

## 🔧 Troubleshooting

### "Connection refused" or "Could not resolve host"

All environments are on **private subnets**. You need network access (VPN / direct connect) to reach the map-storage endpoints. If you can't connect:

```bash
# Option: Port-forward via kubectl
kubectl port-forward svc/virtual-office-map-storage 8080:80 -n default

# Then use localhost
MAP_STORAGE_URL=http://localhost:8080/map-storage ./scripts/cleanup-maps.sh
```

### HTTP 401 Unauthorized

Wrong username or password. Verify your credentials work in the Map Storage UI first.

### HTTP 500 on DELETE (maps with spaces)

The map-storage server has a known bug: it doesn't `decodeURIComponent` on DELETE paths. Maps with spaces/parentheses in their names can't be deleted individually. Use `cleanup-maps.sh` — it automatically falls back to the empty-zip-upload approach.

### Build fails on `npm run build`

```bash
# Clean slate
rm -rf node_modules package-lock.json dist
npm install
npm run build
```

### Pre-commit hook not running

```bash
# Re-initialize husky
npx husky init
```
