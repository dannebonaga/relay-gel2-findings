#!/usr/bin/env bash
# Q029 live8 — cari alamat ResolverSandbox live: scan logs kontrak PoolDrawResolver (dev)
# dan event logs tx dari resolver. Fallback: scan bytecode SANDBOX di seluruh tx? mahal.
# Pendekatan: PoolDrawResolver menerbitkan event via execute(); sandbox dibuat di ctor
# resolver → CREATE address deterministic dari nonce deployer.
RPC=https://rpc-devnet.relay.link
IP=3.216.127.49
gd() { curl -s -m 25 -k --resolve rpc-devnet.relay.link:443:$IP -X POST $RPC -H 'Content-Type: application/json' -d "$1"; }
PDR=0x37218c140017353a4a53be128f74e99acae665db
echo "=== PoolDrawResolver nonce / txcount ==="
echo "txcount: $(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionCount\",\"params\":[\"$PDR\",\"latest\"]}")"
echo "=== logs dari PDR (50k chunks) ==="
LATEST=$(gd '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | python3 -c "import sys,json;print(int(json.load(sys.stdin)['result'],16))")
echo "latest=$LATEST"
FROM=0
while [ $FROM -le $LATEST ]; do
  TO=$((FROM+49999)); [ $TO -gt $LATEST ] && TO=$LATEST
  R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$PDR\",\"fromBlock\":\"$(printf '0x%x' $FROM)\",\"toBlock\":\"$(printf '0x%x' $TO)\"}]}")
  if echo "$R" | grep -q '"result"'; then
    echo "$R" | python3 -c "
import sys,json
try: r=json.load(sys.stdin)['result']
except: sys.exit()
for l in r:
    print('PDR LOG blk',int(l['blockNumber'],16),'tx',l['transactionHash'],'topics',[t[:20] for t in l['topics']])
" 2>/dev/null
  else
    echo "chunk $FROM-$TO: $(echo $R | head -c 90)"
  fi
  FROM=$((TO+1))
done
echo "=== deployer of PDR: cari via tx creation? gunakan eth_getTransactionByAddress tidak ada; skip ==="
