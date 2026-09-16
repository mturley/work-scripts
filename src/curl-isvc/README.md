# curl-isvc

Sends an OpenAI-compatible chat-completions request to a ready KServe `InferenceService`. It identifies a fully ready predictor pod, temporarily port-forwards its model API to `localhost:8080`, discovers the served model ID, submits the prompt, prints the formatted JSON response, and always stops the port-forward before exiting.

## Requirements

- macOS (uses `lsof` to safely check port `8080`)
- `oc` authenticated to the target cluster
- `curl`
- `jq`

## Usage

```bash
curl-isvc [project] <inference-service> <prompt>
```

The project is optional. When omitted, `curl-isvc` uses the current project from `oc project -q`.

```bash
# Use the current oc project
curl-isvc test-llama-chat 'Reply with exactly: NIM inference succeeded'

# Explicitly choose a project
curl-isvc mturley test-llama-chat 'Reply with exactly: NIM inference succeeded'
```

## Behavior

1. Verifies that the specified `InferenceService` is Ready.
2. Finds a Running predictor pod where every container is ready.
3. Refuses to run if another process already listens on `localhost:8080`; it never kills or replaces that listener.
4. Port-forwards `localhost:8080` to the predictor pod's model port (`8000`).
5. Calls `GET /v1/models` to obtain `data[0].id`.
6. Sends the supplied prompt to `POST /v1/chat/completions` and prints the JSON response.
7. Stops the temporary port-forward on success, failure, Ctrl-C, or termination.

The command targets models that expose the OpenAI-compatible `/v1/models` and `/v1/chat/completions` API, such as LLM NIM deployments. It will report the endpoint response if a selected model does not support that API.
