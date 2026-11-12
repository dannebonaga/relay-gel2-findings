#!/usr/bin/env bash
# Q029 live9 — dapatkan OWNER dari PoolDrawResolver? (Punya EXECUTOR/HUB immutable,
# SANDBOX public). SANDBOX() selector = keccak("SANDBOX()")[0:4] — hitung via cast.
RPC=https://rpc-devnet.relay.link
IP=3.216.127.49
gd() { curl -s -m 25 -k --resolve rpc-devnet.relay.link:443:$IP -X POST $RPC -H 'Content-Type: application/json' -d "$1"; }
PDR=0x37218c140017353a4a53be128f74e99acae665db
SEL=$(cast sig "SANDBOX()" 2>/dev/null)
echo "SANDBOX() selector: $SEL"
R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$PDR\",\"data\":\"$SEL\"},\"latest\"]}")
echo "sandbox raw: $R"
SBX=$(echo "$R" | python3 -c "import sys,json;r=json.load(sys.stdin).get('result','');print('0x'+r[-40:] if len(r)>=40 else '')")
echo "sandbox addr: $SBX"
if [ -n "$SBX" ]; then
  echo "sandbox native: $(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$SBX\",\"latest\"]}")"
  echo "sandbox code: $(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"$SBX\",\"latest\"]}" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('result','')))")"
  # WETH9 dev balance
  WETH_DEV=0x45046c91ea0c5c70f0b485209edab8e04dabc0bf
  D=0x70a08231000000000000000000000000${SBX#0x}
  echo "sandbox WETH9: $(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$WETH_DEV\",\"data\":\"$D\"},\"latest\"]}")"
fi
# juga OWNER() selector utk cross-check pemanggil run()
SELO=$(cast sig "OWNER()" 2>/dev/null)
echo "OWNER() sel: $SELO"
RO=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$SBX\",\"data\":\"$SELO\"},\"latest\"]}")
echo "sandbox OWNER: $RO"
