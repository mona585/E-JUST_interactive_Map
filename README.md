<div align="center">

# 📍 E-JUST Interactive Map & Anyplace Indoor Navigation System
### *Production-Grade Self-Hosting & Deployment Architecture Guide*

[![Server](https://img.shields.io/badge/Backend-Scala_Play_2.8_%7C_MongoDB-DC382D?style=for-the-badge&logo=scala&logoColor=white)](server/)
[![Web Suite](https://img.shields.io/badge/Frontend-Nginx_%7C_HTML5_%7C_AngularJS-009639?style=for-the-badge&logo=nginx&logoColor=white)](clients/web/)
[![Android Client](https://img.shields.io/badge/Android-SDK_31_%7C_Java_17-3DDC84?style=for-the-badge&logo=android&logoColor=white)](clients/android-new/)
[![OS Support](https://img.shields.io/badge/OS_Target-Android_12_--_17-0052CC?style=for-the-badge&logo=android&logoColor=white)](apks/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE.txt)

---

</div>

## 📑 Table of Contents
1. [Overview & Production Architecture](#-overview--production-architecture)
2. [Prerequisites & System Requirements](#-prerequisites--system-requirements)
3. [Step 1: Database Setup (MongoDB)](#-step-1-database-setup-mongodb)
4. [Step 2: Backend Server Deployment (Scala / Play 2.8)](#-step-2-backend-server-deployment-scala--play-28)
5. [Step 3: Reverse Proxy, Nginx & SSL Setup (HTTPS)](#-step-3-reverse-proxy-nginx--ssl-setup-https)
6. [Step 4: Web Applications Setup (Architect & Viewer)](#-step-4-web-applications-setup-architect--viewer)
7. [Step 5: Android Mobile Suite Setup (Logger App)](#-step-5-android-mobile-suite-setup-logger-app)
8. [Step 6: Production Operations & Systemd Services](#-step-6-production-operations--systemd-services)
9. [Troubleshooting & Verification Checklist](#-troubleshooting--verification-checklist)

---

## 🏛️ Overview & Production Architecture

The **E-JUST Interactive Map & Anyplace Navigation System** provides GPS-less indoor positioning, crowdsourced Wi-Fi fingerprinting (RSSI), and multi-floor navigation.

### Production Network Topology

```
                   +--------------------------------------------------+
                   |                 CLIENT LAYER                     |
                   |                                                  |
                   |   [ Android Logger / Navigator ]    [ Web Browser ] |
                   +-----------------------+--------------------------+
                                           |
                                 HTTPS (Port 443 / SSL)
                                           v
                   +--------------------------------------------------+
                   |               REVERSE PROXY (Nginx)              |
                   |    - SSL Termination (Let's Encrypt)             |
                   |    - Serves Static Web Apps (/architect, /viewer)|
                   |    - Proxies API Requests (/api/v4) -> Port 9000 |
                   +-----------------------+--------------------------+
                                           |
                                HTTP (Port 9000 internal)
                                           v
                   +--------------------------------------------------+
                   |             ANYPLACE BACKEND SERVER              |
                   |       (Play Framework 2.8 / Scala 2.13)         |
                   +-----------------------+--------------------------+
                                           |
                                  TCP (Port 27017)
                                           v
                   +--------------------------------------------------+
                   |                MONGODB DATABASE                  |
                   |    - Stores Buildings, Floors, POIs, Wi-Fi Maps  |
                   +--------------------------------------------------+
```

---

## 📋 Prerequisites & System Requirements

### Hardware Requirements (Server)
* **CPU:** 4 Cores or higher
* **RAM:** 8 GB RAM minimum (16 GB recommended for high concurrent Wi-Fi logging)
* **Disk:** 50 GB NVMe / SSD Storage

### Software Environment
* **OS:** Ubuntu Linux 20.04 LTS / 22.04 LTS
* **Java:** OpenJDK 17 (`openjdk-17-jdk`)
* **Scala & SBT:** Scala 2.13.x & SBT 1.5+
* **Database:** MongoDB Community Server 4.4 / 5.0 / 6.0
* **Web Server:** Nginx & Certbot (Let's Encrypt)
* **Android Build Tools:** Android SDK Platform 31, Build-Tools `30.0.3`

---

## 🗄️ Step 1: Database Setup (MongoDB)

### 1.1 Install MongoDB Server
On your Ubuntu production server, install MongoDB:

```bash
sudo apt-get update
sudo apt-get install -y gnupg curl

# Import MongoDB GPG key & repository
curl -fsSL https://www.mongodb.org/static/pgp/server-5.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-5.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-5.0.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list

sudo apt-get update
sudo apt-get install -y mongodb-org

# Enable and start MongoDB
sudo systemctl daemon-reload
sudo systemctl enable mongod
sudo systemctl start mongod
```

### 1.2 Configure Anyplace Database & Indexes
Ensure MongoDB is running on `127.0.0.1:27017`. Create the database:

```bash
mongosh --eval "use anyplace"
```

---

## ⚙️ Step 2: Backend Server Deployment (Scala / Play 2.8)

### 2.1 Clone Repository with Submodules
Clone the repository recursively on your server:

```bash
git clone --recurse-submodules https://github.com/mona585/E-JUST_interactive_Map.git /var/www/anyplace
cd /var/www/anyplace/server
```

### 2.2 Configure Private Application Settings
Create private configuration from the example template:

```bash
cp conf/app.private.example.conf conf/app.private.conf
```

Edit `conf/app.private.conf` with your text editor (`nano conf/app.private.conf`):

```hocon
# Application Secret Key (generate a random 64-char string)
play.http.secret.key = "c3VwZXItc2VjcmV0LXByb2R1Y3Rpb24ta2V5LWZvci1lcmp1c3QtYW55cGxhY2Utc2VydmVy"

# Server Base URL
server.address = "https://your-domain.com"

# Database Configuration
mongodb.uri = "mongodb://127.0.0.1:27017/anyplace"

# Password Encryption Salt & Pepper
password.salt = "anyplace_salt_ejust_2026"
password.pepper = "anyplace_pepper_ejust_2026"

# Filesystem Roots
floorPlansRootDir = "/var/www/anyplace/data/floorplans"
radioMapRawDir = "/var/www/anyplace/data/radiomap/raw"
radioMapFrozenDir = "/var/www/anyplace/data/radiomap/frozen"
tilerRootDir = "/var/www/anyplace/server/anyplace_tiler"
```

Create necessary data directories:
```bash
sudo mkdir -p /var/www/anyplace/data/floorplans /var/www/anyplace/data/radiomap/raw /var/www/anyplace/data/radiomap/frozen
sudo chown -R $USER:$USER /var/www/anyplace/data
```

### 2.3 Compile & Package Production Binary
Use SBT to compile and produce a standalone production ZIP distribution:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
sbt clean compile dist
```

Unzip the distribution package:
```bash
cd target/universal
unzip anyplace-4.3.1.zip
sudo mv anyplace-4.3.1 /opt/anyplace-server
```

---

## 🔒 Step 3: Reverse Proxy, Nginx & SSL Setup (HTTPS)

> ⚠️ **CRITICAL NOTE FOR ANDROID 9+ (Android 12–17):**
> Android enforces HTTPS for all network requests. Running the backend on cleartext HTTP will block mobile connections. **SSL via Nginx is mandatory.**

### 3.1 Install Nginx & Let's Encrypt Certbot
```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

### 3.2 Create Nginx Configuration
Create `/etc/nginx/sites-available/anyplace.conf`:

```nginx
server {
    server_name your-domain.com;

    # Maximum upload size for floor plans & Wi-Fi signal logs
    client_max_body_size 100M;

    # 1. API Reverse Proxy -> Play Server Port 9000
    location /api/ {
        proxy_pass http://127.0.0.1:9000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 2. Architect Web App
    location /architect {
        alias /var/www/anyplace/clients/web/anyplace_architect;
        index index.html;
        try_files $uri $uri/ /architect/index.html;
    }g

    # 3. Viewer Campus Web App
    location /viewer {
        alias /var/www/anyplace/clients/web/anyplace_viewer_campus;
        index index.html;
        try_files $uri $uri/ /viewer/index.html;
    }

    # 4. Developer API Portal
    location /developers {
        alias /var/www/anyplace/clients/web/developers;
        index index.html;
    }

    # Root redirect
    location / {
        redirect /viewer;
    }
}
```

Enable site & obtain SSL certificate:
```bash
sudo ln -s /etc/nginx/sites-available/anyplace.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Obtain free SSL Certificate
sudo certbot --nginx -d your-domain.com
```

---

## 🌐 Step 4: Web Applications Setup (Architect & Viewer)

### 4.1 Update Web App API Configuration
Configure the web frontends to communicate with your self-hosted backend.

Edit `/var/www/anyplace/clients/web/anyplace_architect/app.js` or `config.json`:
```javascript
window.ANYPLACE_SERVER_URL = "https://your-domain.com/api/v4/";
```

Edit `/var/www/anyplace/clients/web/anyplace_viewer_campus/app.js`:
```javascript
window.ANYPLACE_SERVER_URL = "https://your-domain.com/api/v4/";
```

Set permissions:
```bash
sudo chown -R www-data:www-data /var/www/anyplace/clients/web
```

---

## 📱 Step 5: Android Mobile Suite Setup (Logger App)

The **Anyplace Logger App** is used by campus managers to record Wi-Fi signals indoors.

### 5.1 Build Requirements & Environment
On your build computer / developer machine:
* Install **JDK 17**
* Set `JAVA_HOME=/usr/lib/jvm/java-1.17.0-openjdk-amd64`
* Ensure Android SDK Platform 31 & Build-Tools `30.0.3` are installed.

### 5.2 Configure Default Server URL in Android Code
To point the built APK to your self-hosted server by default, edit:
`clients/android-new/lib-android/src/main/res/values/strings.xml`:

```xml
<string name="default_pref_server_host">your-domain.com</string>
<string name="default_pref_server_port">443</string>
<string name="default_pref_server_protocol">https</string>
```

### 5.3 Compile Release & Debug APKs
From `clients/android-new/`:

```bash
cd clients/android-new
export JAVA_HOME=/usr/lib/jvm/java-1.17.0-openjdk-amd64

# Assemble Debug APK
./gradlew :logger:assembleDebug
```

> ⚙️ **Automated APK Destination:**
> The build script automatically copies the output APK to [`apks/logger-debug.apk`](apks/logger-debug.apk) in the repository root.

### 5.4 Installation via ADB
```bash
adb install -r ../../apks/logger-debug.apk
```

---

## 🛠️ Step 6: Production Operations & Systemd Services

### 6.1 Create Systemd Service for Anyplace Backend
Create `/etc/systemd/system/anyplace.service`:

```ini
[Unit]
Description=Anyplace Indoor Navigation Play Backend Server
After=network.target mongod.service
Requires=mongod.service

[Service]
Type=simple
User=mesba7
WorkingDirectory=/opt/anyplace-server
ExecStart=/opt/anyplace-server/bin/anyplace -Dhttp.port=9000 -Dconfig.file=/var/www/anyplace/server/conf/application.conf
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=anyplace-server

[Install]
WantedBy=multi-user.target
```

Enable & start service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable anyplace
sudo systemctl start anyplace
sudo systemctl status anyplace
```

---

## 🔍 Troubleshooting & Verification Checklist

| Component | Test Command / Endpoint | Expected Output |
| :--- | :--- | :--- |
| **MongoDB** | `mongosh --eval "db.adminCommand('ping')"` | `{ ok: 1 }` |
| **Backend API Version** | `curl -k https://your-domain.com/api/v4/version` | `{"status":"success","version":"4.3.1"}` |
| **Architect Web App** | Browser: `https://your-domain.com/architect` | Interactive Campus Map & Floor Editor |
| **Viewer Web App** | Browser: `https://your-domain.com/viewer` | Campus Navigation View |
| **Android Settings** | In Logger App: Tap ⚙️ **Settings** | Opens Anyplace Server Settings without crash |
| **APK Build** | `./gradlew :logger:assembleDebug` | `BUILD SUCCESSFUL` -> Output in `apks/logger-debug.apk` |

---

## 📜 License & Citation

* **License:** [MIT License](LICENSE.txt)
* **Citation:**  
  *The Anyplace 4.0 IoT Localization Architecture*, IEEE MDM 2020.  
  *Paschalis Mpeis, Thierry Roussel, Manish Kumar, Constantinos Costa, Christos Laoudias, Denis Capot-Ray, Demetrios Zeinalipour-Yazti.*
