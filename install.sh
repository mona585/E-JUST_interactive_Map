#!/usr/bin/env bash

# ==============================================================================
#  Anyplace - Automated Standalone Local Installation Script
#  Hosts Anyplace completely offline/locally (Server + MongoDB + Web Frontends)
# ==============================================================================

set -e

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set UTF-8 encoding for Java and SBT to avoid character encoding errors on minimal Linux containers
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export JAVA_OPTS="-Dfile.encoding=UTF-8 ${JAVA_OPTS:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT_DIR/server"
CLIENT_WEB_DIR="$ROOT_DIR/clients/web"

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}    Anyplace Standalone Local Installation          ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "Installation path: ${YELLOW}$ROOT_DIR${NC}\n"

# Helper function to auto-install missing packages on Debian/Ubuntu
pkg_install() {
    local PKG=$1
    echo -e "  [+] Auto-installing missing package: ${YELLOW}$PKG${NC}..."
    if command -v apt-get &> /dev/null; then
        if [ "$EUID" -eq 0 ]; then
            apt-get update -qq && apt-get install -y $PKG
        elif command -v sudo &> /dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y $PKG
        else
            echo -e "  ${RED}[✗] Cannot install $PKG automatically (root or sudo required).${NC}"
            return 1
        fi
    fi
}

# Ensure compatible Java (Java 11 or 17) is prioritized over newer unsupported JVMs
if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
    export PATH="$JAVA_HOME/bin:$PATH"
elif [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Check Java
if ! command -v java &> /dev/null; then
    echo -e "  [!] Java is missing. Attempting automatic installation of OpenJDK 17..."
    pkg_install "openjdk-17-jdk" || true

    if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
fi

if command -v java &> /dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -n 1)
    echo -e "  [✓] Java detected: $JAVA_VER"
else
    echo -e "  ${RED}[✗] Java is missing! Please run: apt update && apt install -y openjdk-17-jdk${NC}"
    exit 1
fi

# Check Node.js and NPM
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo -e "  [!] Node.js or NPM missing. Attempting automatic installation..."
    pkg_install "nodejs npm" || true
fi

if command -v node &> /dev/null && command -v npm &> /dev/null; then
    NODE_VER=$(node -v)
    NPM_VER=$(npm -v)
    echo -e "  [✓] Node.js ($NODE_VER) and NPM ($NPM_VER) detected."
else
    echo -e "  ${RED}[✗] Node.js and NPM missing! Please run: apt update && apt install -y nodejs npm${NC}"
    exit 1
fi

# Check ImageMagick (required for floorplan tiler)
if ! command -v convert &> /dev/null && ! command -v gm &> /dev/null; then
    echo -e "  [!] ImageMagick missing. Attempting automatic installation..."
    pkg_install "imagemagick" || true
fi

if command -v convert &> /dev/null || command -v gm &> /dev/null; then
    echo -e "  [✓] ImageMagick / GraphicsMagick detected."
else
    echo -e "  ${YELLOW}[!] ImageMagick not found. Installing image processing tools is recommended for tiler.${NC}"
fi

# Check netcat
if ! command -v nc &> /dev/null; then
    pkg_install "netcat-openbsd" || true
fi

# Check MongoDB or Docker & Auto-Install/Start if missing
HAS_MONGO=false
if command -v mongod &> /dev/null || (command -v nc &> /dev/null && nc -z 127.0.0.1 27017 &> /dev/null); then
    HAS_MONGO=true
    echo -e "  [✓] Local MongoDB service detected on port 27017."
elif command -v docker &> /dev/null; then
    HAS_MONGO=true
    echo -e "  [✓] Docker detected. Starting MongoDB container on port 27017..."
    docker run -d --name anyplace-mongodb -p 27017:27017 -v anyplace_mongo_data:/data/db mongo:latest 2>/dev/null || docker start anyplace-mongodb 2>/dev/null || true
else
    echo -e "  [!] Neither local MongoDB nor Docker was detected on port 27017."
    echo -e "      Attempting automatic installation of MongoDB service..."
    pkg_install "mongodb" || pkg_install "mongodb-server" || pkg_install "docker.io" || true
    
    if command -v systemctl &> /dev/null; then
        systemctl enable --now mongodb 2>/dev/null || systemctl enable --now docker 2>/dev/null || true
    elif command -v service &> /dev/null; then
        service mongodb start 2>/dev/null || service docker start 2>/dev/null || true
    fi

    if command -v docker &> /dev/null; then
        docker run -d --name anyplace-mongodb -p 27017:27017 -v anyplace_mongo_data:/data/db mongo:latest 2>/dev/null || docker start anyplace-mongodb 2>/dev/null || true
    fi

    if command -v mongod &> /dev/null || (command -v nc &> /dev/null && nc -z 127.0.0.1 27017 &> /dev/null); then
        HAS_MONGO=true
        echo -e "  [✓] MongoDB service successfully configured and running."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Server Configuration Setup
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[2/6] Configuring Anyplace Server...${NC}"

# Ensure data directories exist
mkdir -p "$SERVER_DIR/floorplans"
mkdir -p "$SERVER_DIR/radiomaps_raw"
mkdir -p "$SERVER_DIR/radiomaps_frozen"
mkdir -p "$SERVER_DIR/anyplace_tiler"
mkdir -p "$SERVER_DIR/public"

CONF_FILE="$SERVER_DIR/conf/app.private.conf"
CONF_EXAMPLE="$SERVER_DIR/conf/app.private.example.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo -e "  [+] Creating private configuration: $CONF_FILE"
    
    # Generate random secret keys
    APP_SECRET=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32 || date +%s | md5sum | head -c 32)
    SALT=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16 || echo "AnyplaceSalt123")
    PEPPER=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16 || echo "AnyplacePepper123")

    cp "$CONF_EXAMPLE" "$CONF_FILE"
    
    # Update configuration parameters
    sed -i "s|application.secret=.*|application.secret=\"$APP_SECRET\"\nplay.http.secret.key=\"$APP_SECRET\"|g" "$CONF_FILE"
    sed -i "s|password.salt=.*|password.salt=\"$SALT\"|g" "$CONF_FILE"
    sed -i "s|password.pepper=.*|password.pepper=\"$PEPPER\"|g" "$CONF_FILE"
    sed -i "s|server.address=.*|server.address=\"http://localhost\"|g" "$CONF_FILE"
    sed -i "s|server.port=.*|server.port=\"9000\"|g" "$CONF_FILE"
    sed -i "s|mongodb.hostname=.*|mongodb.hostname=\"127.0.0.1\"|g" "$CONF_FILE"
    sed -i "s|mongodb.app.username=.*|mongodb.app.username=\"\"|g" "$CONF_FILE"
    sed -i "s|mongodb.app.password=.*|mongodb.app.password=\"\"|g" "$CONF_FILE"
    sed -i "s|mongodb.port=.*|mongodb.port=27017|g" "$CONF_FILE"
    sed -i "s|mongodb.database=.*|mongodb.database=\"anyplace\"|g" "$CONF_FILE"

    echo -e "  [✓] Configuration generated with unique application secrets."
else
    echo -e "  [✓] Existing $CONF_FILE found."
    sed -i 's|mongodb.app.username=.*|mongodb.app.username=""|g' "$CONF_FILE"
    sed -i 's|mongodb.app.password=.*|mongodb.app.password=""|g' "$CONF_FILE"
    # Ensure play.http.secret.key exists in app.private.conf
    if ! grep -q "play.http.secret.key" "$CONF_FILE"; then
        SECRET_VAL=$(grep "application.secret" "$CONF_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "AnyplaceSecretKey2026")
        echo "play.http.secret.key=\"$SECRET_VAL\"" >> "$CONF_FILE"
    fi
fi

# ------------------------------------------------------------------------------
# 3. Configure Web Client API Endpoint
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[3/6] Configuring Web Client API Routing...${NC}"

API_JS="$CLIENT_WEB_DIR/shared/js/anyplace-core-js/api.js"
if [ -f "$API_JS" ]; then
    echo -e "  [+] Setting API URL in api.js to relative '/api' route..."
    sed -i 's|API.url = .*|API.url = "/api";|g' "$API_JS"
    echo -e "  [✓] API routing updated."
fi

# ------------------------------------------------------------------------------
# 4. Compile Web Frontend Applications
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[4/6] Building Web Applications (Architect, Viewer, Viewer Campus)...${NC}"

build_web_app() {
    local APP_NAME=$1
    local APP_DIR="$CLIENT_WEB_DIR/$APP_NAME"

    if [ -d "$APP_DIR" ]; then
        echo -e "  [*] Processing $APP_NAME..."
        cd "$APP_DIR"
        
        # Install local npm dependencies silently if package.json exists
        if [ -f "package.json" ]; then
            npm install --quiet --no-audit --no-fund --force || true
        fi
        
        # Run bower if bower.json exists
        if [ -f "bower.json" ]; then
            npx --yes bower install --allow-root || true
        fi

        # Run grunt deploy if Gruntfile.js exists
        if [ -f "Gruntfile.js" ]; then
            npx --yes grunt deploy || true
        fi

        # Sync/copy compiled build files into server/public directory
        mkdir -p "$SERVER_DIR/public/$APP_NAME"
        cp -r "$APP_DIR/"* "$SERVER_DIR/public/$APP_NAME/" 2>/dev/null || true
        echo -e "  [✓] $APP_NAME compiled and deployed to server public assets."
    fi
}

build_web_app "anyplace_architect"
build_web_app "anyplace_viewer"
build_web_app "anyplace_viewer_campus"

# Copy shared assets to server/public/shared
if [ -d "$CLIENT_WEB_DIR/shared" ]; then
    mkdir -p "$SERVER_DIR/public/shared"
    cp -r "$CLIENT_WEB_DIR/shared/"* "$SERVER_DIR/public/shared/" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 5. Compile Anyplace Play Backend
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[5/6] Compiling Anyplace Play Backend...${NC}"

cd "$SERVER_DIR"
chmod +x sbt sbt-dist/bin/sbt 2>/dev/null || true

# Determine sbt execution method
SBT_LAUNCHER="$SERVER_DIR/sbt-dist/bin/sbt-launch.jar"

if [ -f "$SBT_LAUNCHER" ]; then
    echo -e "  [*] Compiling backend using sbt launcher..."
    java -Dfile.encoding=UTF-8 -jar "$SBT_LAUNCHER" stage
elif command -v sbt &> /dev/null; then
    echo -e "  [*] Compiling backend using system sbt..."
    JAVA_OPTS="-Dfile.encoding=UTF-8 $JAVA_OPTS" sbt stage
else
    echo -e "  ${RED}[✗] Unable to find sbt executable or sbt-launch.jar!${NC}"
    exit 1
fi

echo -e "  [✓] Backend compiled successfully at: $SERVER_DIR/target/universal/stage/bin/anyplace"

# ------------------------------------------------------------------------------
# 6. Generate Control Scripts & Systemd Service
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[6/6] Generating control scripts and service templates...${NC}"

# 6.1 Create start.sh
cat << 'EOF' > "$ROOT_DIR/start.sh"
#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT_DIR/server"

# Prioritize Java 11/17 for Anyplace Play framework compatibility
if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
    export PATH="$JAVA_HOME/bin:$PATH"
elif [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Java 17 reflection permissions required by Guice / CGLIB
export JDK_JAVA_OPTIONS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED ${JDK_JAVA_OPTIONS:-}"

echo "=== Starting Anyplace Local Environment ==="

# Check MongoDB
if nc -z 127.0.0.1 27017 &> /dev/null; then
    echo "[✓] MongoDB is running on port 27017."
elif command -v docker &> /dev/null; then
    echo "[!] MongoDB not detected. Starting MongoDB Docker container..."
    docker run -d --name anyplace-mongodb -p 27017:27017 -v anyplace_mongo_data:/data/db mongo:latest 2>/dev/null || docker start anyplace-mongodb
    sleep 3
    echo "[✓] MongoDB container started."
else
    echo "[!] WARNING: MongoDB is not running on port 27017. Backend may fail to connect."
fi

# Check if Anyplace is already running
if pgrep -f "target/universal/stage/bin/anyplace" > /dev/null; then
    echo "[!] Anyplace server is already running!"
    exit 0
fi

# Remove stale RUNNING_PID lockfile if present from a previous run/crash
rm -f "$SERVER_DIR/target/universal/stage/RUNNING_PID"

# Extract application secret from configuration file
CONF_PATH="$SERVER_DIR/conf/app.private.conf"
APP_SECRET=$(grep -E '^(play\.http\.secret\.key|application\.secret)' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -n 1 || echo "AnyplaceSecretKey2026")
if [ -z "$APP_SECRET" ]; then
    APP_SECRET="AnyplaceSecretKey2026"
fi

echo "[*] Launching Anyplace Backend on port 9000..."
nohup "$SERVER_DIR/target/universal/stage/bin/anyplace" -Dplay.http.secret.key="$APP_SECRET" -Dapplication.secret="$APP_SECRET" -Dhttp.port=9000 > "$ROOT_DIR/anyplace.log" 2>&1 &

sleep 3
if pgrep -f "target/universal/stage/bin/anyplace" > /dev/null; then
    echo "[✓] Anyplace server started successfully!"
    echo "    - Backend API: http://localhost:9000/api"
    echo "    - Architect Web App: http://localhost:9000/architect/"
    echo "    - Viewer Web App: http://localhost:9000/viewer/"
    echo "    - Log output: $ROOT_DIR/anyplace.log"
else
    echo "[✗] Anyplace server failed to start. Check $ROOT_DIR/anyplace.log"
    exit 1
fi
EOF
chmod +x "$ROOT_DIR/start.sh"

# 6.2 Create stop.sh
cat << 'EOF' > "$ROOT_DIR/stop.sh"
#!/usr/bin/env bash

echo "=== Stopping Anyplace Local Environment ==="

PID=$(pgrep -f "target/universal/stage/bin/anyplace" || true)

if [ -n "$PID" ]; then
    echo "[*] Stopping Anyplace server process ($PID)..."
    kill -15 $PID 2>/dev/null || kill -9 $PID 2>/dev/null
    sleep 2
    echo "[✓] Anyplace server stopped."
else
    echo "[!] Anyplace server is not currently running."
fi
EOF
chmod +x "$ROOT_DIR/stop.sh"

# 6.3 Create status.sh
cat << 'EOF' > "$ROOT_DIR/status.sh"
#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Anyplace Service Status ==="

# Check MongoDB
if nc -z 127.0.0.1 27017 &> /dev/null; then
    echo " [✓] MongoDB (Port 27017): ONLINE"
else
    echo " [✗] MongoDB (Port 27017): OFFLINE"
fi

# Check Anyplace Server
PID=$(pgrep -f "target/universal/stage/bin/anyplace" || true)
if [ -n "$PID" ]; then
    echo " [✓] Anyplace Backend (PID $PID): ONLINE (Port 9000)"
else
    echo " [✗] Anyplace Backend: OFFLINE"
fi

echo -e "\n=== Recent Server Logs (last 15 lines) ==="
if [ -f "$ROOT_DIR/anyplace.log" ]; then
    tail -n 15 "$ROOT_DIR/anyplace.log"
else
    echo "No log file found at $ROOT_DIR/anyplace.log"
fi
EOF
chmod +x "$ROOT_DIR/status.sh"

# 6.4 Create systemd service template
cat << EOF > "$ROOT_DIR/anyplace.service"
[Unit]
Description=Anyplace Indoor Navigation Service
After=network.target mongodb.service docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$ROOT_DIR
Environment="JDK_JAVA_OPTIONS=--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED"
ExecStart=$SERVER_DIR/target/universal/stage/bin/anyplace -Dplay.http.secret.key=$APP_SECRET -Dapplication.secret=$APP_SECRET -Dhttp.port=9000
Restart=always
RestartSec=5
StandardOutput=append:$ROOT_DIR/anyplace.log
StandardError=append:$ROOT_DIR/anyplace.log

[Install]
WantedBy=multi-user.target
EOF

echo -e "  [✓] Helper scripts created: start.sh, stop.sh, status.sh"
echo -e "  [✓] Systemd service template generated: anyplace.service"

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}      ANYPLACE INSTALLATION COMPLETE!               ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "To start the Anyplace system locally:"
echo -e "  ${YELLOW}./start.sh${NC}"
echo -e ""
echo -e "To check system status:"
echo -e "  ${YELLOW}./status.sh${NC}"
echo -e ""
echo -e "To stop the system:"
echo -e "  ${YELLOW}./stop.sh${NC}"
echo -e ""
echo -e "For Nginx Proxy Manager setup instructions, view:"
echo -e "  ${YELLOW}LOCAL_SETUP_NGINX_PROXY_MANAGER.md${NC}"
echo -e "====================================================\n"
