# Scripts

Utility scripts for operating the platform.

| Script | Purpose |
|--------|---------|
| `load-test.sh` | Concurrent load test against the vLLM InferenceService. Reports throughput and latency. |

## Usage

```bash
# Port-forward to the InferenceService first
kubectl port-forward -n inference svc/mistral-7b-predictor 8080:80

# In another terminal
export CONCURRENT=8
export REQUESTS_PER_WORKER=50
./scripts/load-test.sh
```
