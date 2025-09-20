#!/usr/bin/env bash
set -euo pipefail

# generator_amnezia.sh
# Генератор AmneziaWG-конфига (Cloudflare WARP -> Amnezia format)
# Требует: wg (wireguard-tools), jq, curl, openssl (или fallback /dev/urandom + xxd)
#
# Usage:
#   ./generator_amnezia.sh            # сгенерит новый приватный ключ и Amnezia-конфиг
#   ./generator_amnezia.sh <privkey>  # использовать существующий приватный ключ
# Option:
#   I1_BYTES env var: размер I1 в байтах (по умолчанию 256). Пример: I1_BYTES=512 ./generator_amnezia.sh

# --- параметры (можно менять) ---
API="https://api.cloudflareclient.com/v0i1909051800"
ENDPOINT="162.159.192.1:500"    # стандартный WARP endpoint, оставляем по умолчанию
DEFAULT_DNS="1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001"
I1_BYTES="${I1_BYTES:-512}"     # 256 bytes -> 512 hex chars. Увеличь если нужно.

# Amnezia параметры (типичные)
S1=0
S2=0
Jc=120
Jmin=23
Jmax=911
H1=1
H2=2
H3=3
H4=4
MTU=1280

# приватный ключ: если передан как аргумент — используем его, иначе сгенерим
priv="${1:-$(wg genkey)}"
pub="${2:-$(echo "${priv}" | wg pubkey)}"

# функции для запросов
ins() { curl -s -H 'user-agent:' -H 'content-type: application/json' -X "$1" "${API}/$2" "${@:3}"; }
sec() { ins "$1" "$2" -H "authorization: Bearer $3" "${@:4}"; }

# 1) Регистрация устройства
echo "Registering device at Cloudflare WARP API..."
resp=$(ins POST "reg" -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%T.000Z)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")
id=$(echo "$resp" | jq -r '.result.id // empty')
token=$(echo "$resp" | jq -r '.result.token // empty')

if [ -z "$id" ] || [ -z "$token" ]; then
  echo "ERROR: registration failed. Full API response:"
  echo "$resp"
  exit 1
fi

# 2) Включаем warp
resp2=$(sec PATCH "reg/${id}" "$token" -d '{"warp_enabled":true}')

# извлекаем peer/pub/адреса
peer_pub=$(echo "$resp2" | jq -r '.result.config.peers[0].public_key // empty')
client_ipv4=$(echo "$resp2" | jq -r '.result.config.interface.addresses.v4 // empty')
client_ipv6=$(echo "$resp2" | jq -r '.result.config.interface.addresses.v6 // empty')

if [ -z "$peer_pub" ] || [ -z "$client_ipv4" ]; then
  echo "ERROR: API did not return required fields. Full response:"
  echo "$resp2"
  exit 1
fi

echo "Got peer public key and addresses:"
echo " - peer_pub: ${peer_pub:0:8}..."
echo " - IPv4: $client_ipv4"
echo " - IPv6: $client_ipv6"

# 3) Сгенерировать I1 (hex). Попробуем openssl, иначе fallback
if command -v openssl >/dev/null 2>&1; then
  I1_HEX="$(openssl rand -hex "${I1_BYTES}" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
elif command -v xxd >/dev/null 2>&1; then
  I1_HEX="$(head -c "${I1_BYTES}" /dev/urandom | xxd -p -u | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
else
  # базовый fallback: base64 -> hex (меньше энтропии, но работает)
  I1_HEX="$(head -c "${I1_BYTES}" /dev/urandom | base64 | xxd -p -u | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
fi

I1_FIELD="<b 0x${I1_HEX}>"

# 4) Формируем AmneziaWG-конфиг. ВАЖНО: порядок полей оставлен в виде, совместимом с Amnezia.
cat > warp.conf <<EOF
[Interface]
PrivateKey = ${priv}
S1 = ${S1}
S2 = ${S2}
Jc = ${Jc}
Jmin = ${Jmin}
Jmax = ${Jmax}
H1 = ${H1}
H2 = ${H2}
H3 = ${H3}
H4 = ${H4}
MTU = ${MTU}
I1 = ${I1_FIELD}
Address = ${client_ipv4}, ${client_ipv6}
DNS = ${DEFAULT_DNS}

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${ENDPOINT}
EOF

echo "✅ AmneziaWG config generated: warp.conf"
