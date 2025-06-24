#!/bin/bash

set -e

# --- Конфигурация ---
INSTALL_DIR=~/cysic-verifier-docker
PROXY_FILE="proxy.txt"
PROXY_MAP_DIR="proxy_map"

# --- Проверка и установка Docker ---
function install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "Docker не найден. Устанавливаем Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \\
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    echo "Docker установлен."
  else
    echo "Docker уже установлен."
  fi

  if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
    echo "Docker Compose не найден. Устанавливаем..."
    # Добавьте установку docker-compose, если нужно
  else
    echo "Docker Compose уже установлен."
  fi
}

install_docker

# --- Ввод пользователя ---
read -p "Введите количество контейнеров verifier для запуска (например, 5): " NUM_CONTAINERS
if ! [[ "$NUM_CONTAINERS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Ошибка: нужно ввести положительное число."
  exit 1
fi

read -p "Введите claim_reward_address (Ethereum адрес): " CLAIM_REWARD_ADDRESS
if ! [[ "$CLAIM_REWARD_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
  echo "Ошибка: неверный формат Ethereum адреса."
  exit 1
fi

read -p "Введите паузу между запуском контейнеров в секундах (например, 5): " PAUSE_SEC
if ! [[ "$PAUSE_SEC" =~ ^[0-9]+$ ]]; then
  echo "Ошибка: нужно ввести неотрицательное число."
  exit 1
fi

# --- Подготовка ---
mapfile -t ALL_PROXIES < "$PROXY_FILE"
mkdir -p "$PROXY_MAP_DIR"
USED_PROXIES=()

if [ "${#ALL_PROXIES[@]}" -lt "$NUM_CONTAINERS" ]; then
  echo "❌ Недостаточно прокси: нужно $NUM_CONTAINERS, найдено ${#ALL_PROXIES[@]}"
  exit 1
fi

assign_proxy() {
  local cname=$1

  if [ -f "$PROXY_MAP_DIR/$cname" ]; then
    cat "$PROXY_MAP_DIR/$cname"
    return
  fi

  for proxy in "${ALL_PROXIES[@]}"; do
    if ! printf '%s\n' "${USED_PROXIES[@]}" | grep -q "^$proxy$"; then
      echo "$proxy" > "$PROXY_MAP_DIR/$cname"
      USED_PROXIES+=("$proxy")
      echo "$proxy"
      return
    fi
  done

  echo "❌ Не осталось свободных прокси" >&2
  exit 1
}

# --- Удаление старых контейнеров и подготовка директорий ---
echo "🧹 Удаляем старые контейнеры и директории..."
for i in $(seq 1 $NUM_CONTAINERS); do
  docker rm -f verifier$i 2>/dev/null || true
  rm -rf "$INSTALL_DIR/config/verifier$i"
  rm -f "$PROXY_MAP_DIR/verifier$i"
done

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# --- Скачивание бинарников ---
echo "⬇️ Скачиваем бинарники и библиотеки..."
curl -L -o verifier https://github.com/cysic-labs/cysic-phase3/releases/download/v1.0.0/verifier_linux
curl -L -o libdarwin_verifier.so https://github.com/cysic-labs/cysic-phase3/releases/download/v1.0.0/libdarwin_verifier.so
curl -L -o librsp.so https://github.com/cysic-labs/cysic-phase3/releases/download/v1.0.0/librsp.so
chmod +x verifier

# --- start.sh ---
echo "✍️ Создаём start.sh..."
cat > start.sh <<EOF
#!/bin/bash
cp /root/.cysic/config.yaml ./config.yaml
export CHAIN_ID=534352
LD_LIBRARY_PATH=. ./verifier
EOF
chmod +x start.sh

# --- Dockerfile ---
echo "📦 Создаём Dockerfile..."
cat > Dockerfile <<EOF
FROM ubuntu:22.04

WORKDIR /app

RUN apt-get update && apt-get install -y libstdc++6 libgcc-s1 bash ca-certificates && update-ca-certificates

COPY verifier .
COPY libdarwin_verifier.so .
COPY librsp.so .
COPY start.sh .

RUN chmod +x verifier start.sh

CMD ["./start.sh"]
EOF

# --- docker-compose.yml ---
echo "📝 Создаём docker-compose.yml и конфиги..."
echo "version: '3.8'" > docker-compose.yml
echo "services:" >> docker-compose.yml

for i in $(seq 1 $NUM_CONTAINERS); do
  CNAME="verifier$i"
  mkdir -p config/$CNAME/keys
  cat > config/$CNAME/config.yaml <<YAML
chain:
  endpoint: "grpc-testnet.prover.xyz:80"
  chain_id: "cysicmint_9001-1"
  gas_coin: "CYS"
  gas_price: 10

claim_reward_address: "$CLAIM_REWARD_ADDRESS"

server:
  cysic_endpoint: "https://ws-pre.prover.xyz"
YAML

  PROXY=$(assign_proxy "$CNAME")
  IP=$(echo "$PROXY" | cut -d: -f1)
  PORT=$(echo "$PROXY" | cut -d: -f2)
  USER=$(echo "$PROXY" | cut -d: -f3)
  PASS=$(echo "$PROXY" | cut -d: -f4)
  PROXY_URL="http://$USER:$PASS@$IP:$PORT"

  cat >> docker-compose.yml <<SERVICE
  $CNAME:
    build: .
    container_name: $CNAME
    environment:
      - CHAIN_ID=534352
      - http_proxy=$PROXY_URL
      - https_proxy=$PROXY_URL
    volumes:
      - ./config/$CNAME:/root/.cysic
    restart: always
SERVICE

done

# --- Сборка и запуск ---
echo "🚧 Собираем докер-образы..."
docker compose build

echo "🚀 Запускаем контейнеры с паузой $PAUSE_SEC секунд..."
for i in $(seq 1 $NUM_CONTAINERS); do
  docker compose up -d verifier$i
  echo "✅ Контейнер verifier$i запущен."
  if [ "$i" -lt "$NUM_CONTAINERS" ]; then
    sleep "$PAUSE_SEC"
  fi
done

echo "🎉 Готово! $NUM_CONTAINERS контейнеров verifier запущены."
