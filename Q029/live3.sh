#!/usr/bin/env bash
# Q029 live check 3 — WETH9 (prod) & testnet dev: poolDeployed events from factory
# + WETH9 balanceOf(poolDrawResolver/multicall3) on devnet via eth_call
RPC_MAIN=https://rpc.chain.relay.link
RPC_DEV=https://rpc.testnet.relay.link
IP=3.216.127.49
WETH_MAIN=0xf02a2b5defadc5148cea9f8705b86ef1f9a6aea2  # stag? listed in stag.json... check dev
gd() { curl -s -m 20 -k --resolve rpc.testnet.relay.link:443:$IP -X POST $RPC_DEV -H 'Content-Type: application/json' -d "$1"; }
gm() { curl -s -m 20 -X POST $RPC_MAIN -H 'Content-Type: application/json' -d "$1"; }

# dev WETH9
WETH_DEV=0x45046c91ea0c5c70f0b485209edab8e04dabc0bf
# topic0 = keccak("PoolDeployed(address,address,bytes32)")
TOPIC=0x$(cast keccak "PoolDeployed(address,address,bytes32)" 2>/dev/null || echo need_cast)
echo "topic0=$TOPIC"

FACTORY=0x354426693ed9f0facefe4399326a236f122f46d7
# scan logs per-chunk 50k blocks on devnet
LATEST_HEX=$(gd '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | python3 -c "import sys,json;print(json.load(sys.stdin)['result'])")
LATEST=$((16#$(echo $LATEST_HEX | sed 's/^0x//')))
echo "dev latest block: $LATEST"
FROM=0
LOGLIST=""
while [ $FROM -lt $LATEST ]; do
  TO=$((FROM+50000)); [ $TO -gt $LATEST ] && TO=$LATEST
  R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$FACTORY\",\"fromBlock\":\"$(printf '0x%x' $FROM)\",\"toBlock\":\"$(printf '0x%x' $TO)\"}]}")
  if echo "$R" | grep -q '"result"'; then
    N=$(echo "$R" | python3 -c "import sys,json;r=json.load(sys.stdin)['result'];print(len(r));[print('POOL:',l['address'] if False else l['topics'][1],l['topics'][2],l['topics'][3],l['blockNumber']) for l in r]")
    if [ "$N" != "0" ]; then echo "chunk $FROM-$TO: $N pools"; fi
  else
    echo "chunk $FROM-$TO err: $(echo $R | head -c 120)"
  fi
  FROM=$((TO+1))
done
echo "=== WETH9 balanceOf dev targets ==="
# balanceOf(address) selector 0x70a08231
for A in 0x37218c140017353a4a53be128f74e99acae665db 0x5365b15ea11403d8eb92fa7df8506882585037e5; do
  D=0x70a08231000000000000000000000000${A#0x}
  R=$(gd "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$WETH_DEV\",\"data\":\"$D\"},\"latest\"]}")
  echo "WETH(dev) $A -> $R"
done
echo "=== WETH9 (main) balanceOf Multicall3 prod ==="
for A in 0x03a246e0bff569bca1cc76d25d6529a86b6154d3 0xb24ac15b9da6d88e283ffe048befe02e188ea64e; do
  D=0x70a08231000000000000000000000000${A#0x}
  R=$(gm "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$WETH_MAIN\",\"data\":\"$D\"},\"latest\"]}")
  echo "WETH(main) $A -> $R"
done
