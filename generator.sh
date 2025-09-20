#!/usr/bin/env bash
set -euo pipefail

# generator_amnezia.sh
# Генератор AmneziaWG-конфига на основе Cloudflare WARP API.
# Требует: wg (wireguard-tools), jq, curl, openssl (или /dev/urandom)
#
# Usage:
#   ./generator_amnezia.sh            # сгенерит новый приватный ключ и Amnezia-конфиг
#   ./generator_amnezia.sh <privkey>  # используем переданный приватный ключ
# Опционально: задать длину I1 hex-ключа в байтах через переменную окружения I1_BYTES

# Параметры: можно передать приватный ключ как аргумент
priv="${1:-$(wg genkey)}"
pub="${2:-$(echo "${priv}" | wg pubkey)}"

API="https://api.cloudflareclient.com/v0i1909051800"

ins() { curl -s -H 'user-agent:' -H 'content-type: application/json' -X "$1" "${API}/$2" "${@:3}"; }
sec() { ins "$1" "$2" -H "authorization: Bearer $3" "${@:4}"; }

# Регистрация и активация WARP
response=$(ins POST "reg" -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%T.000Z)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")
id=$(echo "$response" | jq -r '.result.id // empty')
token=$(echo "$response" | jq -r '.result.token // empty')

if [ -z "$id" ] || [ -z "$token" ]; then
  echo "ERROR: registration failed. API response:"
  echo "$response"
  exit 1
fi

response=$(sec PATCH "reg/${id}" "$token" -d '{"warp_enabled":true}')

peer_pub=$(echo "$response" | jq -r '.result.config.peers[0].public_key // empty')
client_ipv4=$(echo "$response" | jq -r '.result.config.interface.addresses.v4 // empty')
client_ipv6=$(echo "$response" | jq -r '.result.config.interface.addresses.v6 // empty')

if [ -z "$peer_pub" ] || [ -z "$client_ipv4" ]; then
  echo "ERROR: API did not return required fields:"
  echo "$response"
  exit 1
fi

# Параметры Amnezia (можно изменить при необходимости)
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
ENDPOINT="162.159.192.1:500"

# Длина I1 в байтах (по умолчанию 256 байт -> 512 hex символов).
# Если хочешь длиннее — установи переменную окружения I1_BYTES.
I1_BYTES="${I1_BYTES:-256}"

# Генерируем I1 (hex). Используем openssl если есть, иначе /dev/urandom -> xxd.
if command -v openssl >/dev/null 2>&1; then
  I1_HEX="$(openssl rand -hex "${I1_BYTES}" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
else
  # fallback
  I1_HEX="$(head -c "${I1_BYTES}" /dev/urandom | xxd -p -u | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
fi

I1_FIELD="<b 0x${I1_HEX}>"

# Собираем конфиг AmneziaWG
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
DNS = 1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${ENDPOINT}
EOF

echo "✅ AmneziaWG config generated and saved to warp.conf"
