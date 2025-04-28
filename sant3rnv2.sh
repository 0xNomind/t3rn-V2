#!/bin/bash

# Menampilkan ASCII Art untuk "Saandy"
echo "
  ██████ ▄▄▄     ▄▄▄      ███▄    █▓█████▓██   ██▓
▒██    ▒▒████▄  ▒████▄    ██ ▀█   █▒██▀ ██▒██  ██▒
░ ▓██▄  ▒██  ▀█▄▒██  ▀█▄ ▓██  ▀█ ██░██   █▌▒██ ██░
  ▒   ██░██▄▄▄▄█░██▄▄▄▄██▓██▒  ▐▌██░▓█▄   ▌░ ▐██▓░
▒██████▒▒▓█   ▓██▓█   ▓██▒██░   ▓██░▒████▓ ░ ██▒▓░
▒ ▒▓▒ ▒ ░▒▒   ▓▒█▒▒   ▓▒█░ ▒░   ▒ ▒ ▒▒▓  ▒  ██▒▒▒ 
░ ░▒  ░ ░ ▒   ▒▒ ░▒   ▒▒ ░ ░░   ░ ▒░░ ▒  ▒▓██ ░▒░ 
░  ░  ░   ░   ▒   ░   ▒     ░   ░ ░ ░ ░  ░▒ ▒ ░░  
      ░       ░  ░    ░  ░        ░   ░   ░ ░     
                                    ░     ░ ░     
"

# Prompt untuk user (default: root)
read -p "Masukkan nama user untuk menjalankan executor (default: root): " EXECUTOR_USER
EXECUTOR_USER=${EXECUTOR_USER:-root}

# Hentikan dan hapus service lama jika ada
if systemctl list-units --full -all | grep -q "t3rn-executor.service"; then
    sudo systemctl stop t3rn-executor.service
    sudo systemctl disable t3rn-executor.service
    sudo systemctl daemon-reload
fi

# Hapus file lama
sudo rm -rf /home/$EXECUTOR_USER/t3rn
sudo rm -rf /etc/systemd/system/t3rn-executor.service
sudo rm -rf /etc/t3rn-executor.env

# Prompt untuk Private Key
while [[ -z "$PRIVATE_KEY_LOCAL" ]]; do
    read -sp "Masukkan PRIVATE_KEY_LOCAL (tidak boleh kosong): " PRIVATE_KEY_LOCAL
    echo ""
done

# Prompt Alchemy API Keys
while [[ -z "$APIKEY_ALCHEMY_LIST" ]]; do
    read -p "Masukkan semua API Key INFURA (pisahkan dengan koma): " APIKEY_ALCHEMY_LIST
    echo
done

# Prompt Gas Price
while [[ -z "$GAS_PRICE" ]]; do
    read -p "Gas Price (tidak boleh kosong): " GAS_PRICE
    echo
done

# Proses API keys menjadi array
IFS=',' read -ra APIKEYS <<< "$APIKEY_ALCHEMY_LIST"

# Build URLs
ARBT_URLS=""
BAST_URLS=""
BLST_URLS=""
OPST_URLS=""
UNIT_URLS=""

for api in "${APIKEYS[@]}"; do
    api_cleaned=$(echo "$api" | xargs)  # Hapus spasi
    ARBT_URLS+="\"https://arbitrum-sepolia.infura.io/v3/$api_cleaned\", "
    BAST_URLS+="\"https://base-sepolia.infura.io/v3/$api_cleaned\", "
    BLST_URLS+="\"https://blast-sepolia.infura.io/v3/$api_cleaned\", "
    OPST_URLS+="\"https://optimism-sepolia.infura.io/v3/$api_cleaned\", "
    UNIT_URLS+="\"https://unichain-sepolia.infura.io/v3/$api_cleaned\", "
done

# Hilangkan koma terakhir
ARBT_URLS=${ARBT_URLS%, }
BAST_URLS=${BAST_URLS%, }
BLST_URLS=${BLST_URLS%, }
OPST_URLS=${OPST_URLS%, }
UNIT_URLS=${UNIT_URLS%, }

INSTALL_DIR="/home/$EXECUTOR_USER/t3rn"
SERVICE_FILE="/etc/systemd/system/t3rn-executor.service"
ENV_FILE="/etc/t3rn-executor.env"
EXECUTOR_VERSION=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | grep 'tag_name' | cut -d\" -f4)
EXECUTOR_FILE="executor-linux-$EXECUTOR_VERSION.tar.gz"
EXECUTOR_URL="https://github.com/t3rn/executor-release/releases/download/$EXECUTOR_VERSION/$EXECUTOR_FILE"

# Pastikan direktori ada
mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

# Cek koneksi sebelum mengunduh
if curl --output /dev/null --silent --head --fail "$EXECUTOR_URL"; then
    echo "🔽 Mengunduh Executor dari $EXECUTOR_URL..."
    curl -L -o "$EXECUTOR_FILE" "$EXECUTOR_URL"
else
    echo "❌ URL tidak dapat diakses, pastikan koneksi internet stabil."
    exit 1
fi

# Ekstrak file
echo "📦 Mengekstrak Executor..."
tar -xzvf "$EXECUTOR_FILE" || {
    echo "❌ Gagal mengekstrak file. Pastikan format file benar."
    exit 1
}

# Bersihkan file unduhan
rm -f "$EXECUTOR_FILE"

# Pindah ke direktori executor
if [ -d "executor/executor/bin" ]; then
    cd executor/executor/bin || exit 1
    echo "✅ Executor berhasil diunduh dan diekstrak."
else
    echo "❌ Direktori 'executor/executor/bin' tidak ditemukan! Ekstraksi mungkin gagal."
    exit 1
fi

# Konfigurasi environment file
sudo bash -c "cat > $ENV_FILE" <<EOL
RPC_ENDPOINTS='{
  "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/public", "http://b2n.rpc.caldera.xyz/http"],
  "mont": ["https://testnet-rpc.monad.xyz"],
  "arbt": [$ARBT_URLS],
  "bast": [$BAST_URLS],
  "blst": [$BLST_URLS],
  "opst": [$OPST_URLS],
  "unit": [$UNIT_URLS]
}'
EXECUTOR_MAX_L3_GAS_PRICE="$GAS_PRICE"
PRIVATE_KEY_LOCAL="$PRIVATE_KEY_LOCAL"
ENABLED_NETWORKS="l2rn,arbitrum-sepolia,base-sepolia,optimism-sepolia"
EOL

# Berikan hak akses ke user
sudo chown -R "$EXECUTOR_USER":"$EXECUTOR_USER" "$INSTALL_DIR"
sudo chmod 600 "$ENV_FILE"

# Buat systemd service
sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=t3rn Executor Service
After=network.target

[Service]
User=$EXECUTOR_USER
WorkingDirectory=$INSTALL_DIR/executor/executor/bin
ExecStart=$INSTALL_DIR/executor/executor/bin/executor
Restart=always
RestartSec=10
Environment=ENVIRONMENT=testnet
Environment=LOG_LEVEL=debug
Environment=LOG_PRETTY=false
Environment=EXECUTOR_PROCESS_BIDS_ENABLED=true
Environment=EXECUTOR_PROCESS_ORDERS_ENABLED=true
Environment=EXECUTOR_PROCESS_CLAIMS_ENABLED=true
Environment=EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=false
Environment=EXECUTOR_PROCESS_ORDERS_API_ENABLED=false
EnvironmentFile=$ENV_FILE
Environment=ENABLED_NETWORKS=l2rn,arbitrum-sepolia,base-sepolia,blst-sepolia,optimism-sepolia,unichain-sepolia,monad-testnet 

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd dan jalankan service
sudo systemctl daemon-reload
sudo systemctl enable t3rn-executor.service
sudo systemctl start t3rn-executor.service

# Tampilkan status layanan dan log secara real-time
echo "✅ Executor berhasil diinstall. Menampilkan status dan log..."
sudo systemctl status t3rn-executor.service --no-pager
sudo journalctl -u t3rn-executor.service -f --no-hostname -o cat
