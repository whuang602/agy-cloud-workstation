# Antigravity 2.0 Google Cloud Workstation Image

A production-ready custom container image for [Google Cloud Workstations](https://cloud.google.com/workstations) that runs **Google Antigravity (AGY) 2.0** as the primary interface inside an in-browser GNOME desktop session via noVNC.

---

## Features

- **Antigravity 2.0**: Pre-installed in `/opt/Antigravity-x64` and configured via `/etc/xdg/autostart/antigravity.desktop` to launch automatically full-screen upon desktop session startup.
- **Google Chrome**: Pre-installed and registered as the system-wide default browser (`http`, `https`, `text/html`) with container-compatible flags (`--no-sandbox`, `--test-type`, `--disable-dev-shm-usage`) for seamless Google OAuth authentication.
- **In-Browser Web Desktop**: Runs TigerVNC and noVNC on **Port 80**, letting you connect directly through Cloud Workstations' IAM/SSO-authenticated web proxy without opening public ports.
- **Persistent State**: Retains user configs (`~/.gemini/antigravity-cli`), settings, and projects via attached persistent home disk (`/home/user`).
- **Optimized Cloud Build**: Includes a configured `cloudbuild.yaml` leveraging `E2_HIGHCPU_8` machine types for fast (~6–8 min) builds.

---

## Repository Structure

```
.
├── Dockerfile                    # Image build definition (GNOME, VNC, AGY 2.0, Chrome)
├── cloudbuild.yaml               # Google Cloud Build configuration
├── LICENSE                       # Apache 2.0 License
├── README.md                     # Documentation & usage guide
└── assets/                       # Cloud Workstations systemd & startup integration
    ├── google/scripts/entrypoint.sh
    ├── opt/noVNC/index.html
    ├── etc/systemd/system/
    │   ├── novnc.service
    │   └── tigervnc.service
    └── etc/workstation-startup.d/
        ├── 100_add-xstartup.sh
        └── 100_persist-machine-id.sh
```

---

## Quickstart: Build and Deploy

### 1. Prerequisites & APIs

Ensure required Google Cloud APIs are enabled:

```bash
gcloud services enable \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    workstations.googleapis.com
```

Create a Docker repository in Artifact Registry if you don't already have one:

```bash
export REGION="us-central1"
export REPO_NAME="workstations"

gcloud artifacts repositories create ${REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Docker repository for Cloud Workstations custom images"
```

---

### 2. Build the Image with Cloud Build

From the root of this repository, submit the build:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export REPO_NAME="workstations"
export IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/agy-workstation:latest"

gcloud builds submit --substitutions _IMAGE_NAME="${IMAGE_TAG}" .
```

---

### 3. Create Cloud Workstation Configuration

Create your workstation cluster and configuration pointing to the custom image:

```bash
export CLUSTER_NAME="agy-cluster"
export CONFIG_NAME="agy-config"

# Create cluster (if not already existing)
gcloud workstations clusters create $CLUSTER_NAME \
    --region=$REGION

# Create workstation configuration
gcloud workstations configs create $CONFIG_NAME \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --machine-type="e2-standard-4" \
    --pd-disk-type="pd-standard" \
    --pd-disk-size=50 \
    --pool-size=0 \
    --idle-timeout="7200s" \
    --container-custom-image="${IMAGE_TAG}"
```

> **Important Configuration Tips:**
> - **`--pd-disk-type="pd-standard"` & `--pd-disk-size=50`**: Avoids exhausting regional SSD quotas (`SSD_TOTAL_GB`).
> - **`--pool-size=0`**: Disables pre-warmed idle standby VMs so you are not billed for compute when no workstations are running.
> - **`--idle-timeout="7200s"`**: Automatically shuts down the instance after 2 hours of inactivity.

---

### 4. Create and Start the Workstation

```bash
export WORKSTATION_NAME="my-agy-box"

# Create instance
gcloud workstations create $WORKSTATION_NAME \
    --cluster=$CLUSTER_NAME \
    --config=$CONFIG_NAME \
    --region=$REGION

# Start instance
gcloud workstations start $WORKSTATION_NAME \
    --cluster=$CLUSTER_NAME \
    --config=$CONFIG_NAME \
    --region=$REGION
```

---

### 5. Connect

1. In the [Google Cloud Console](https://console.cloud.google.com/workstations), navigate to **Cloud Workstations** > **Workstations**.
2. Find your workstation (`my-agy-box`) and click **"Connect"** (or **"Connect to web app"**).
3. The browser tab opens the remote desktop session via noVNC on Port 80, with **Antigravity 2.0 open and ready to use**.

---

## Credits & License

This project is licensed under the **Apache License 2.0**. See the [LICENSE](LICENSE) file for the full text.

Derived from Google Cloud Platform's [cloud-workstations-custom-image-examples](https://github.com/GoogleCloudPlatform/cloud-workstations-custom-image-examples) (GNOME / noVNC example), Copyright 2024 Google LLC.
