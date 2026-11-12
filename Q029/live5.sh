#!/usr/bin/env bash
# Q029 live5 — disambiguate endpoint chain: code at dev-hub vs prod-hub
RPC=https://rpc.testnet.relay.link
IP=3.216.127.49
gd() { curl -s -m 25 -k --resolve rpc.testnet.relay.link:443:$IP -X POST $RPC -H 'Content-Type: application/json' -d "$1"; }
for A in 0xa884543c91156098b2e50ae17c3840770b7b55f5 0xDDD361727C22A01EB137880678A20b0BEaE69318 0x37218c140017353a4a53be128f74e99acae665db 0x5365b15ea11403d8eb92fa7df8506882585037e5; do
  R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"$A\",\"latest\"]}")
  L=$(echo "$R" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('result','')))")
  echo "$A codelen=$L"
done
echo "=== same on main rpc ==="
gm() { curl -s -m 25 -X POST https://rpc.chain.relay.link -H 'Content-Type: application/json' -d "$1"; }
for A in 0xa884543c91156098b2e50ae17c3840770b7b55f5 0xDDD361727C22A01EB137880678A20b0BEaE69318 0x5365b15ea11403d8eb92fa7df8506882585037e5; do
  R=$(gm "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"$A\",\"latest\"]}")
  L=$(echo "$R" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('result','')))")
  echo "$A codelen=$L"
done
