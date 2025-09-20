#!/bin/bash
set -e

# Генерация приватного ключа (WireGuard) и производного публичного ключа
PRIV_KEY="${1:-$(wg genkey)}"
PUB_KEY="$(echo "$PRIV_KEY" | wg pubkey)"

# Генерация "I1" ключа для AmneziaWG — 512 байт (1024 символа в hex)
I1_KEY=$(openssl rand -hex 512)

# Статические параметры, как в рабочем конфиге AmneziaWG
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
ADDRESS="172.16.0.2, 2606:4700:110:836d:61ea:bf9f:a59d:fb03"
DNS="1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001"
PEER_PUBLIC_KEY="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
ENDPOINT="162.159.192.1:500"

# Генерация конфигурации
cat > warp.conf <<EOM
[Interface]
PrivateKey = $PRIV_KEY
S1 = $S1
S2 = $S2
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
MTU = $MTU
I1 = <b $I1_KEY>
Address = $ADDRESS
DNS = $DNS

[Peer]
PublicKey = $PEER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $ENDPOINT
EOM

echo "✅ warp.conf для AmneziaWG сгенерирован"
