#!/usr/bin/env bash
#
# curl-isvc — send an OpenAI-compatible chat-completions request to a KServe
# InferenceService through a temporary local port-forward.
#
# Usage: curl-isvc [project] <inference-service> <prompt>
#

set -euo pipefail

LOCAL_PORT=8080
REMOTE_PORT=8000

usage() {
  cat <<'EOF'
Usage: curl-isvc [project] <inference-service> <prompt>

Sends an OpenAI-compatible POST /v1/chat/completions request to a ready KServe
InferenceService. The command finds its ready predictor pod, temporarily
port-forwards localhost:8080 to the pod's port 8000, discovers its model ID
from GET /v1/models, sends the supplied prompt, prints the response, and then
stops the port-forward.

Arguments:
  project             Optional OpenShift namespace. Defaults to the current oc project.
  inference-service   Required name of the KServe InferenceService
  prompt              Required user-message content to send to the model

Examples:
  curl-isvc test-llama-chat 'Reply with exactly: NIM inference succeeded'
  curl-isvc mturley test-llama-chat 'Reply with exactly: NIM inference succeeded'

Requirements: oc, curl, jq, lsof
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Error: an InferenceService and prompt are required; project is optional." >&2
  usage >&2
  exit 2
fi

project=""
inference_service=""
prompt=""
if [[ $# -eq 3 ]]; then
  project=$1
  inference_service=$2
  prompt=$3
else
  inference_service=$1
  prompt=$2
fi
port_forward_pid=""
port_forward_log=""

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' was not found in PATH." >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "$port_forward_pid" ]] && kill -0 "$port_forward_pid" 2>/dev/null; then
    echo "Stopping temporary port-forward (PID $port_forward_pid)."
    kill "$port_forward_pid" 2>/dev/null || true
    wait "$port_forward_pid" 2>/dev/null || true
  fi
  [[ -n "$port_forward_log" ]] && rm -f "$port_forward_log"
}
trap cleanup EXIT INT TERM

for command in oc curl jq lsof; do
  require_command "$command"
done

if [[ -z "$project" ]]; then
  echo "No project was supplied; reading the current oc project."
  project=$(oc project -q 2>/dev/null) || {
    echo "Error: could not determine the current oc project. Supply the project explicitly." >&2
    exit 1
  }
  if [[ -z "$project" ]]; then
    echo "Error: no current oc project is set. Supply the project explicitly." >&2
    exit 1
  fi
fi

listeners=$(lsof -nP -iTCP:"$LOCAL_PORT" -sTCP:LISTEN 2>/dev/null || true)
if [[ -n "$listeners" ]]; then
  echo "Error: localhost port $LOCAL_PORT is already in use. curl-isvc will not disturb its listener." >&2
  echo "$listeners" >&2
  echo "Stop that process or choose another time after it has released port $LOCAL_PORT." >&2
  exit 1
fi

echo "Checking whether InferenceService '$inference_service' in project '$project' is Ready."
ready=$(oc -n "$project" get inferenceservice "$inference_service" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null) || {
  echo "Error: could not read InferenceService '$inference_service' in project '$project'." >&2
  exit 1
}

if [[ "$ready" != "True" ]]; then
  echo "Error: InferenceService '$inference_service' is not Ready (Ready=${ready:-unknown})." >&2
  echo "Wait for it to become Ready before sending an inference request." >&2
  exit 1
fi

echo "Finding a Ready predictor pod."
pods=$(oc -n "$project" get pods \
  -l "serving.kserve.io/inferenceservice=$inference_service" \
  -o json) || {
  echo "Error: could not list predictor pods for '$inference_service'." >&2
  exit 1
}
pod=$(printf '%s' "$pods" | jq -er '
  [.items[]
   | select(.status.phase == "Running")
   | select((.status.containerStatuses // []) | length > 0)
   | select(all(.status.containerStatuses[]; .ready == true))
   | .metadata.name][0]
') || {
  echo "Error: no fully Ready predictor pod was found for '$inference_service'." >&2
  printf '%s' "$pods" | jq -r '.items[] | "  \(.metadata.name): phase=\(.status.phase // "unknown")"' >&2
  exit 1
}

echo "Using predictor pod '$pod'."
port_forward_log=$(mktemp -t curl-isvc-port-forward.XXXXXX)
echo "Starting temporary port-forward: localhost:$LOCAL_PORT -> $pod:$REMOTE_PORT."
oc -n "$project" port-forward "pod/$pod" "$LOCAL_PORT:$REMOTE_PORT" >"$port_forward_log" 2>&1 &
port_forward_pid=$!

models_file=$(mktemp -t curl-isvc-models.XXXXXX)
payload_file=$(mktemp -t curl-isvc-payload.XXXXXX)
response_file=$(mktemp -t curl-isvc-response.XXXXXX)
trap 'rm -f "$models_file" "$payload_file" "$response_file"; cleanup' EXIT INT TERM

echo "Waiting for the forwarded model API to accept requests."
for _ in $(seq 1 30); do
  if curl --silent --show-error --fail-with-body \
    "http://127.0.0.1:$LOCAL_PORT/v1/models" >"$models_file" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$port_forward_pid" 2>/dev/null; then
    echo "Error: the port-forward exited before the model API became available:" >&2
    cat "$port_forward_log" >&2
    exit 1
  fi
  sleep 1
done

if [[ ! -s "$models_file" ]]; then
  echo "Error: model API did not respond to GET /v1/models within 30 seconds." >&2
  cat "$port_forward_log" >&2
  exit 1
fi

model_id=$(jq -er '.data[0].id' "$models_file") || {
  echo "Error: GET /v1/models did not return a model ID in data[0].id." >&2
  cat "$models_file" >&2
  exit 1
}

echo "Discovered served model ID: $model_id"
echo "Sending the supplied prompt to POST /v1/chat/completions."
jq -n --arg model "$model_id" --arg prompt "$prompt" \
  '{model: $model, messages: [{role: "user", content: $prompt}], temperature: 0, max_tokens: 256, stream: false}' \
  >"$payload_file"

curl --silent --show-error --fail-with-body \
  -H 'Content-Type: application/json' \
  --data @"$payload_file" \
  "http://127.0.0.1:$LOCAL_PORT/v1/chat/completions" >"$response_file"

echo "Inference request succeeded. Response:"
jq . "$response_file"
