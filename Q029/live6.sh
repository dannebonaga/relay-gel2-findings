#!/usr/bin/env bash
# Q029 live6 — devnet scan: factory PoolDeployed logs (50k chunks) + WETH9 dev check
RPC=https://rpc-devnet.relay.link
IP=3.216.127.49
# NOTE: rpc-devnet.relay.link is the devnet endpoint (chainId 0x83471? verify below)
gd() { curl -s -m 25 -k --resolve rpc-devnet.relay.link:443:$IP -X POST $RPC -H 'Content-Type: application/json' -d "$1"; }
echo "=== chainId ==="; gd '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'; echo
F=0x354426693ed9f0facefe4399326a236f122f46d7
LATEST=$(gd '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | python3 -c "import sys,json;print(int(json.load(sys.stdin)['result'],16))")
echo "latest=$LATEST"
FROM=0
while [ $FROM -le $LATEST ]; do
  TO=$((FROM+49999)); [ $TO -gt $LATEST ] && TO=$LATEST
  R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$F\",\"fromBlock\":\"$(printf '0x%x' $FROM)\",\"toBlock\":\"$(printf '0x%x' $TO)\"}]}")
  if echo "$R" | grep -q '"result"'; then
    echo "$R" | python3 -c "
import sys,json
try: r=json.load(sys.stdin)['result']
except: sys.exit()
for l in r:
    print('POOL deployed block',int(l['blockNumber'],16),'deployer','0x'+l['topics'][1][-40:],'pool','0x'+l['topics'][2][-40:])
" 2>/dev/null
  else
    echo "chunk $FROM-$TO: $(echo $R | head -c 100)"
  fi
  FROM=$((TO+1))
done
echo "=== dev WETH9 balances ==="
WETH_DEV=0x45046c91ea0c5c70f0b485209edab8e04dabc0bf
for A in 0x37218c140017353a4a53be128f74e99acae665db 0x5365b15ea11403d8eb92fa7df8506882585037e5; do
  D=0x70a08231000000000000000000000000${A#0x}
  echo "WETH(dev) $A -> $(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$WETH_DEV\",\"data\":\"$D\"},\"latest\"]}")"
done
