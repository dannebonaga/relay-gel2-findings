#!/usr/bin/env bash
# Q029 live7 — final: Multicall3 WETH9 balance check on dev chain + poolDeployed event scan on FACTORY (all logs)
RPC=https://rpc-devnet.relay.link
IP=3.216.127.49
gd() { curl -s -m 25 -k --resolve rpc-devnet.relay.link:443:$IP -X POST $RPC -H 'Content-Type: application/json' -d "$1"; }
gm() { curl -s -m 25 -X POST https://rpc.chain.relay.link -H 'Content-Type: application/json' -d "$1"; }
F=0x354426693ed9f0facefe4399326a236f122f46d7
WETH_DEV=0x45046c91ea0c5c70f0b485209edab8e04dabc0bf
M3_DEV=0x5365b15ea11403d8eb92fa7df8506882585037e5
PDR_DEV=0x37218c140017353a4a53be128f74e99acae665db

echo "=== 1) WETH9(dev) balanceOf(dev multicall3 / poolDrawResolver) ==="
for A in $M3_DEV $PDR_DEV; do
  D=0x70a08231000000000000000000000000${A#0x}
  R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$WETH_DEV\",\"data\":\"$D\"},\"latest\"]}")
  echo "WETH9 dev $A -> $R"
done
echo "=== 2) native balances (dev) ==="
for A in $M3_DEV $PDR_DEV $F; do
  echo "$A -> $(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$A\",\"latest\"]}")"
done
echo "=== 3) factory all-logs scan (dev, 50k chunks) ==="
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
    print('FACTORY LOG blk',int(l['blockNumber'],16),'topics',l['topics'],'data',l['data'][:66])
" 2>/dev/null
  else
    echo "chunk $FROM-$TO: $(echo $R | head -c 90)"
  fi
  FROM=$((TO+1))
done
echo "=== 4) prod: WETH9 bal of prod multicall3 + basicCallResolver (repeat) + native ==="
WETH_STAG=0xf02a2b5defadc5148cea9f8705b86ef1f9a6aea2
for A in 0x03a246e0bff569bca1cc76d25d6529a86b6154d3 0xb24ac15b9da6d88e283ffe048befe02e188ea64e; do
  D=0x70a08231000000000000000000000000${A#0x}
  echo "prod $A WETH=$R"
done
echo done
