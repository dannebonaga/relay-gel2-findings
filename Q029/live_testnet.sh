#!/usr/bin/env bash
# Q029 live check — testnet (dev chain 537724) balances of poolDrawResolver / multicall3 / fundingPoolFactory / basicCallResolver
RPC=https://rpc.testnet.relay.link
g() { curl -s -m 20 -X POST $RPC -H 'Content-Type: application/json' -d "$1"; }

echo "=== chainId ==="
g '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'; echo
echo "=== blockNumber ==="
g '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'; echo

for A in 0x37218c140017353a4a53be128f74e99acae665db 0x5365b15ea11403d8eb92fa7df8506882585037e5 0x354426693ed9f0facefe4399326a236f122f46d7 0xc0f489a34672d5b960a19279d99d77e94221d0c9; do
  B=$(g "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$A\",\"latest\"]}")
  C=$(g "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"$A\",\"latest\"]}")
  echo "$A balance=$B code_len=${#C}"
done
