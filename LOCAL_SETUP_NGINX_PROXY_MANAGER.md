# Local Deployment Guide: Anyplace Behind Nginx Proxy Manager

This document provides step-by-step instructions to deploy the **Anyplace Indoor Navigation System** completely locally (offline / standalone), hosted on your own server, and published securely through an external **Nginx Proxy Manager (NPM)** instance.

---

## System Architecture Overview

```
[ Android App / Web Clients ]
             │
             ▼ HTTPS (443) / HTTP (80)
┌────────────────────────────────────────────────────────┐
│            Nginx Proxy Manager (NPM)                   │
│   (Handles Domain Names, SSL Certificates & Routing)   │
└──────────────────────────┬─────────────────────────────┘
                           │ Reverse Proxy HTTP (Port 9000)
                           ▼
┌────────────────────────────────────────────────────────┐
│            Anyplace Standalone Server                  │
│  ├── Play Server Backend (API & Static Assets: 9000)   │
│  └── MongoDB Database (Port 27017)                      │
└────────────────────────────────────────────────────────┘
```

---

## Quick Start (Single Command Installation)

### Step 1: Clone the Repository & Run Installer

Run the single-command automated installer:

```bash
git clone https://github.com/mona585/E-JUST_interactive_Map.git
cd E-JUST_interactive_Map
chmod +x install.sh
./install.sh
```

What `install.sh` automatically does:
1. Checks dependencies (`Java 11/17`, `Node.js`, `NPM`, `ImageMagick`).
2. Generates private security keys (`application.secret`, `password.salt`, `password.pepper`) in `server/conf/app.private.conf`.
3. Prepares data directories for floorplans, radiomaps, and tiles.
4. Configures `clients/web/shared/js/anyplace-core-js/api.js` to route requests to relative `/api`.
5. Builds Web Applications (`architect`, `viewer`, `viewer_campus`) using NPM/Bower/Grunt.
6. Compiles the Anyplace Play server (`sbt stage`).
7. Generates helper scripts (`start.sh`, `stop.sh`, `status.sh`) and `anyplace.service` for systemd.

---

## Step 2: Start the Local Anyplace Server

Run the `start.sh` script to boot MongoDB and the Anyplace backend:

```bash
./start.sh
```

To verify status:
```bash
./status.sh
```

The Anyplace backend is now running locally on **`http://127.0.0.1:9000`**.

---

## Step 3: Configure Nginx Proxy Manager (NPM)

Log into your **Nginx Proxy Manager Web Admin Interface** (typically running on `http://<your-npm-ip>:81`).

### 1. Add a New Proxy Host

1. Click **Proxy Hosts** -> **Add Proxy Host**.
2. **Details Tab**:
   - **Domain Names**: Enter your local domain or local IP (e.g., `anyplace.local` or `map.yourdomain.com`).
   - **Scheme**: `http`
   - **Forward Hostname / IP**: Enter your Anyplace server host IP (e.g., `127.0.0.1` if NPM is on the same machine, or local server IP `192.168.x.x`, or `172.17.0.1` for Docker host gateway).
   - **Forward Port**: `9000`
   - **Block Common Exploits**: `ON`
   - **Websockets Support**: `ON` *(Required for real-time map updates)*

### 2. Custom Locations Configuration (Recommended)

In the Proxy Host modal, go to the **Custom Locations** tab to ensure clean routing:

| Location | Scheme | Forward Hostname / IP | Forward Port |
| :--- | :--- | :--- | :--- |
| `/api` | `http` | `127.0.0.1` | `9000` |
| `/floortiles` | `http` | `127.0.0.1` | `9000` |
| `/architect` | `http` | `127.0.0.1` | `9000` |
| `/viewer` | `http` | `127.0.0.1` | `9000` |

### 3. SSL Configuration Tab

1. Select **SSL Certificate**: Choose **Request a new SSL Certificate** (Let's Encrypt) or select an existing custom SSL certificate.
2. Check **Force SSL** (recommended).
3. Check **HTTP/2 Support**.
4. Click **Save**.

---

## Step 4: Accessing the Web Interface

Once Nginx Proxy Manager is configured, open your browser and navigate to:

- **Anyplace Architect (Map Creator & Editor)**:
  `https://map.yourdomain.com/architect/`
- **Anyplace Viewer (Navigation App)**:
  `https://map.yourdomain.com/viewer/`
- **API Health Check**:
  `https://map.yourdomain.com/api/version`

---

## Step 5: Connecting the Anyplace Android Client

To connect the Android mobile app (`clients/android-new`) to your local Anyplace instance:

1. Open the Anyplace Android App.
2. Open **Settings** -> **Server Configuration**.
3. Set the **Server URL / Domain** to your NPM URL:
   `https://map.yourdomain.com` (or `http://192.168.x.x:9000`)
4. Save and login with your registered account.

> **Note on Android HTTPS Requirements:**  
> Modern Android versions require valid HTTPS SSL certificates for API requests. Running Nginx Proxy Manager with Let's Encrypt or a trusted CA certificate ensures seamless Android app connectivity.

---

## System Management Commands

| Action | Command |
| :--- | :--- |
| **Start System** | `./start.sh` |
| **Stop System** | `./stop.sh` |
| **Check System Status** | `./status.sh` |
| **View Server Logs** | `tail -f anyplace.log` |

---

## Optional: Register as a System Service (Systemd)

To make Anyplace start automatically whenever the server reboots:

```bash
sudo cp anyplace.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable anyplace
sudo systemctl start anyplace
```
