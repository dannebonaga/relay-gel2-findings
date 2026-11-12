#!/usr/bin/env bash
# Q029 live balance check on Relay Chain
RPC=https://rpc.chain.relay.link
jq_() { python3 -c "import sys,json;print(json.load(sys.stdin).get('result'))"; }

MC3=0x03a246e0bff569bca1cc76d25d6529a86b6154d3
BCR=0xb24ac15b9da6d88e283ffe048befe02e188ea64e

echo "=== chain id ==="
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | jq_

echo "=== Multicall3 native balance (prod) ==="
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$MC3\",\"latest\"]}" | jq_

echo "=== Multicall3 code present? ==="
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"$MC3\",\"latest\"]}" | python3 -c "import sys,json;r=json.load(sys.stdin).get('result','');print('len',len(r))"

echo "=== basicCallResolver native balance (prod) ==="
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$BCR\",\"latest\"]}" | jq_

echo "=== basicCallResolver code present? ==="
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"$BCR\",\"latest\"]}" | python3 -c "import sys,json;r=json.load(sys.stdin).get('result','');print('len',len(r))"

# Sandbox: derive? No — deployed by PoolDrawResolver via new (no deterministic CREATE2 with
# factory args we can recompute). PoolDrawResolver only on dev (chain 537724).
# Query hub for registered resolvers instead? Hub address 0xDDD361727C22A01EB137880678A20b0BEaE69318 (537713).

echo "=== ERC20 (USDC/USDT on Relay Hub?) balances of Multicall3 & basicCallResolver ==="
# try known relay hub tokens via hub? skip token discovery: use WETH9 prod if known; instead
# check native only (done above) + note in findings.
