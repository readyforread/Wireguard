#!/bin/bash
set -e

# Генерация ключей WireGuard, если не переданы
priv="${1:-$(wg genkey)}"
pub="${2:-$(echo "$priv" | wg pubkey)}"

# Cloudflare WARP API
api="https://api.cloudflareclient.com/v0i1909051800"

# Функции для запросов
ins() { curl -s -H 'user-agent:' -H 'content-type: application/json' -X "$1" "${api}/$2" "${@:3}"; }
sec() { ins "$1" "$2" -H "authorization: Bearer $3" "${@:4}"; }

# Регистрация WARP
resp=$(ins POST "reg" -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%T.000Z)\",\"key\":\"$pub\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")
id=$(echo "$resp" | jq -r '.result.id')
token=$(echo "$resp" | jq -r '.result.token')
resp=$(sec PATCH "reg/$id" "$token" -d '{"warp_enabled":true}')

# Извлекаем все данные для AmneziaWG
I1=$(echo "$resp" | jq -r '.result.config.interface.I1')
S1=$(echo "$resp" | jq -r '.result.config.interface.S1')
S2=$(echo "$resp" | jq -r '.result.config.interface.S2')
Jc=$(echo "$resp" | jq -r '.result.config.interface.Jc')
Jmin=$(echo "$resp" | jq -r '.result.config.interface.Jmin')
Jmax=$(echo "$resp" | jq -r '.result.config.interface.Jmax')
H1=$(echo "$resp" | jq -r '.result.config.interface.H1')
H2=$(echo "$resp" | jq -r '.result.config.interface.H2')
H3=$(echo "$resp" | jq -r '.result.config.interface.H3')
H4=$(echo "$resp" | jq -r '.result.config.interface.H4')
addr_v4=$(echo "$resp" | jq -r '.result.config.interface.addresses.v4')
addr_v6=$(echo "$resp" | jq -r '.result.config.interface.addresses.v6')
peer_pub=$(echo "$resp" | jq -r '.result.config.peers[0].public_key')
endpoint=$(echo "$resp" | jq -r '.result.config.peers[0].endpoint')

# Формируем рабочий конфиг AmneziaWG
cat > warp.conf <<EOM
[Interface]
PrivateKey = $priv
S1 = $S1
S2 = $S2
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
MTU = 1280
I1 = $I1
Address = $addr_v4, $addr_v6
DNS = 1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001

[Peer]
PublicKey = $peer_pub
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $endpoint
EOM

echo "✅ Конфиг warp.conf успешно сгенерирован!"
