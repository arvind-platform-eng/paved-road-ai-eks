#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Simple load test for the Mistral 7B InferenceService.
# Sends concurrent OpenAI-compatible completion requests and reports throughput.
# ------------------------------------------------------------------------------
set -euo pipefail

ENDPOINT="${ENDPOINT:-http://localhost:8080}"
CONCURRENT="${CONCURRENT:-4}"
REQUESTS_PER_WORKER="${REQUESTS_PER_WORKER:-25}"
MODEL="${MODEL:-mistral-7b}"

echo "==> Load test configuration"
echo "    Endpoint:              $ENDPOINT"
echo "    Concurrent workers:    $CONCURRENT"
echo "    Requests per worker:   $REQUESTS_PER_WORKER"
echo "    Total requests:        $((CONCURRENT * REQUESTS_PER_WORKER))"
echo "    Model:                 $MODEL"
echo ""

send_request() {
  local worker_id=$1
  local i=$2
  local start=$(date +%s%N)

  local response
  response=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT/v1/completions" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$MODEL\",
      \"prompt\": \"Explain Kubernetes networking in one paragraph.\",
      \"max_tokens\": 100,
      \"temperature\": 0.7
    }")

  local http_code
  http_code=$(echo "$response" | tail -n 1)
  local end=$(date +%s%N)
  local duration_ms=$(( (end - start) / 1000000 ))

  echo "worker=$worker_id req=$i status=$http_code duration_ms=$duration_ms"
}

worker() {
  local worker_id=$1
  for ((i=1; i<=REQUESTS_PER_WORKER; i++)); do
    send_request "$worker_id" "$i"
  done
}

echo "==> Starting workers..."
start_time=$(date +%s)

for ((w=1; w<=CONCURRENT; w++)); do
  worker "$w" &
done

wait

end_time=$(date +%s)
duration=$((end_time - start_time))
total=$((CONCURRENT * REQUESTS_PER_WORKER))

echo ""
echo "==> Done"
echo "    Total duration:  ${duration}s"
echo "    Total requests:  $total"
echo "    Throughput:      $(echo "scale=2; $total / $duration" | bc) req/sec"
