#!/usr/bin/env bash
# Q029 live4 — factory PoolDeployed logs (chunked) + pool residual check
RPC=https://rpc.testnet.relay.link
IP=3.216.127.49
F=0x354426693ed9f0facefe4399326a236f122f46d7
gd() { curl -s -m 25 -k --resolve rpc.testnet.relay.link:443:$IP -X POST $RPC -H 'Content-Type: application/json' -d "$1"; }

LATEST=$(gd '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | python3 -c "import sys,json;print(int(json.load(sys.stdin)['result'],16))")
echo "latest=$LATEST"
FROM=0
POOLS=""
while [ $FROM -le $LATEST ]; do
  TO=$((FROM+49999)); [ $TO -gt $LATEST ] && TO=$LATEST
  R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$F\",\"fromBlock\":\"$(printf '0x%x' $FROM)\",\"toBlock\":\"$(printf '0x%x' $TO)\"}]}")
  if echo "$R" | grep -q '"result"'; then
    CNT=$(echo "$R" | python3 -c "
import sys,json
r=json.load(sys.stdin)['result']
for l in r:
    print('POOL deployed block',int(l['blockNumber'],16),'deployer','0x'+l['topics'][1][-40:],'pool','0x'+l['topics'][2][-40:])
" 2>/dev/null)
    if [ -n "$CNT" ]; then echo "$CNT"; POOLS="$POOLS\n$CNT"; fi
  else
    echo "chunk $FROM-$TO: $(echo $R | head -c 100)"
  fi
  FROM=$((TO+1))
done
echo "=== done scan; pools found above (if any) ==="
