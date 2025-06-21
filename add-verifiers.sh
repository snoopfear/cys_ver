#!/bin/bash

set -e

INSTALL_DIR=~/cysic-verifier-docker
cd "$INSTALL_DIR"

read -p "Сколько новых контейнеров добавить: " COUNT
if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "❌ Нужно ввести положительное число"
  exit 1
fi

# Определяем последний номер контейнера
LAST_NUM=$(grep -oP 'verifier\K[0-9]+' docker-compose.yml | sort -n | tail -n1)
LAST_NUM=${LAST_NUM:-0}
echo "📦 Последний существующий контейнер: verifier$LAST_NUM"

# Берём claim_reward_address из первого существующего
if [ -f "config/verifier1/config.yaml" ]; then
  CLAIM_REWARD_ADDRESS=$(grep 'claim_reward_address:' config/verifier1/config.yaml | awk '{print $2}')
  echo "🔁 Используем адрес claim_reward_address: $CLAIM_REWARD_ADDRESS"
else
  echo "❌ Не найден config/verifier1/config.yaml"
  exit 1
fi

# Генерируем новые контейнеры
for i in $(seq $((LAST_NUM+1)) $((LAST_NUM+COUNT))); do
  echo "⚙️ Создаём конфиг для verifier$i"
  mkdir -p config/verifier$i/keys

  cat > config/verifier$i/config.yaml <<YAML
chain:
  endpoint: "grpc-testnet.prover.xyz:80"
  chain_id: "cysicmint_9001-1"
  gas_coin: "CYS"
  gas_price: 10

claim_reward_address: "\"$CLAIM_REWARD_ADDRESS\""

server:
  cysic_endpoint: "https://ws-pre.prover.xyz"
YAML

  cat >> docker-compose.yml <<EOF

  verifier$i:
    build: .
    container_name: verifier$i
    environment:
      - CHAIN_ID=534352
    volumes:
      - ./config/verifier$i:/root/.cysic
    restart: always
EOF
done

echo "🔨 Пересобираем образ..."
docker compose build

# Запускаем только новые
for i in $(seq $((LAST_NUM+1)) $((LAST_NUM+COUNT))); do
  docker compose up -d verifier$i
  echo "✅ verifier$i запущен"
done
