#!/usr/bin/env bash
#
# jenkins-watch — poll a Jenkins job or build until it completes, then alert.
#
# Usage:
#   jenkins-watch [--env <file>] <job-or-build-url>
#
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: jenkins-watch [--env <file>] <job-or-build-url>

Polls Jenkins every 10 seconds and opens a macOS alert when the build completes.
Requires JENKINS_URL, JENKINS_USER, and JENKINS_API_TOKEN in the environment,
or loaded from the optional --env file.

Examples:
  jenkins-watch https://jenkins.example.com/job/my-job/
  jenkins-watch --env ~/secrets/jenkins.env https://jenkins.example.com/job/my-job/
  jenkins-watch https://jenkins.example.com/job/my-job/42/ --env ~/secrets/jenkins.env
EOF
}

JOB_URL=""
ENV_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --env)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "jenkins-watch: --env requires a file path" >&2
        usage >&2
        exit 2
      fi
      if [[ -n "$ENV_FILE" ]]; then
        echo "jenkins-watch: --env may only be specified once" >&2
        exit 2
      fi
      ENV_FILE=$2
      shift 2
      ;;
    --*)
      echo "jenkins-watch: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$JOB_URL" ]]; then
        echo "jenkins-watch: unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      JOB_URL=$1
      shift
      ;;
  esac
done

if [[ -z "$JOB_URL" ]]; then
  echo "jenkins-watch: missing Jenkins job or build URL" >&2
  usage >&2
  exit 2
fi

if [[ -n "$ENV_FILE" ]]; then
  # Expand a literal ~/ prefix as well as paths expanded by the calling shell.
  case "$ENV_FILE" in
    "~/"*) ENV_FILE="$HOME/${ENV_FILE#\~/}" ;;
  esac
  if [[ ! -r "$ENV_FILE" ]]; then
    echo "jenkins-watch: cannot read environment file: $ENV_FILE" >&2
    exit 1
  fi
  # The supplied file contains KEY=value lines, so export its assignments for
  # curl and the rest of this script. The file is explicitly user-selected.
  set -a
  . "$ENV_FILE"
  set +a
fi

JOB_URL=${JOB_URL%/}
if [[ -z "${JENKINS_URL:-}" || -z "${JENKINS_USER:-}" || -z "${JENKINS_API_TOKEN:-}" ]]; then
  echo "jenkins-watch: JENKINS_URL, JENKINS_USER, and JENKINS_API_TOKEN must be set in the environment or provided by --env" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jenkins-watch: jq is required" >&2
  exit 1
fi
if ! command -v alert >/dev/null 2>&1; then
  echo "jenkins-watch: alert must be available on PATH" >&2
  exit 1
fi

# Accept either a job URL or an individual build URL. Job URLs resolve to their
# latest build; numeric trailing path segments are treated as build numbers.
if [[ "$JOB_URL" =~ /[0-9]+$ ]]; then
  BUILD_URL="$JOB_URL"
  API_URL="$BUILD_URL/api/json?tree=building,result,number"
else
  BUILD_URL=""
  API_URL="$JOB_URL/lastBuild/api/json?tree=building,result,number"
fi

# A curl config on stdin keeps the API token out of curl's command-line args
# (and thus out of process listings). Jenkins API tokens are URL-safe strings.
curl_config() {
  printf 'user = "%s:%s"\n' "$JENKINS_USER" "$JENKINS_API_TOKEN"
}

status_symbol() {
  local symbol color
  case "$1" in
    SUCCESS) symbol='✓'; color='32' ;;
    IN_PROGRESS|BUILDING) symbol='●'; color='36' ;;
    FAILURE|FAILED|ABORTED) symbol='✗'; color='31' ;;
    UNSTABLE|PAUSED_PENDING_INPUT) symbol='!'; color='33' ;;
    QUEUED|NOT_BUILT) symbol='○'; color='34' ;;
    *) symbol='?'; color='90' ;;
  esac
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    printf '\033[%sm%s\033[0m' "$color" "$symbol"
  else
    printf '%s' "$symbol"
  fi
}

printf 'Watching Jenkins build at %s\n' "$JOB_URL"
PIPELINE_NOTICE_SHOWN=0
while true; do
  printf '\n'
  printf '[%s] Requesting build status: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$API_URL"
  if ! response=$(curl --silent --show-error --fail --max-time 20 --config <(curl_config) "$API_URL"); then
    echo "jenkins-watch: failed to query Jenkins; retrying in 10 seconds" >&2
    sleep 10
    continue
  fi

  if ! jq -e 'has("building") and (.building | type == "boolean")' >/dev/null <<< "$response"; then
    echo "jenkins-watch: Jenkins returned an unexpected build status; retrying in 10 seconds" >&2
    sleep 10
    continue
  fi

  building=$(jq -r '.building' <<< "$response")
  build_number=$(jq -r '.number // "unknown"' <<< "$response")
  if [[ -z "$BUILD_URL" ]]; then
    BUILD_URL="$JOB_URL/$build_number"
  fi

  pipeline_url="$BUILD_URL/wfapi/describe"
  printf '[%s] Requesting pipeline stages: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pipeline_url"
  pipeline_response=$(curl --silent --show-error --fail --max-time 20 --config <(curl_config) "$pipeline_url" 2>/dev/null || true)
  if jq -e '.stages | type == "array"' >/dev/null <<< "$pipeline_response" 2>/dev/null; then
    while IFS=$'\t' read -r stage_id stage_name stage_status; do
      [[ -z "$stage_name" ]] && continue
      printf '[%s] ' "$(date '+%Y-%m-%d %H:%M:%S')"
      status_symbol "$stage_status"
      printf ' Stage: %s — %s\n' "$stage_name" "$stage_status"
      if [[ "$stage_status" == "IN_PROGRESS" ]]; then
        node_url="$BUILD_URL/execution/node/$stage_id/wfapi/describe"
        node_response=$(curl --silent --show-error --fail --max-time 20 --config <(curl_config) "$node_url" 2>/dev/null || true)
        if jq -e '.stageFlowNodes | type == "array"' >/dev/null <<< "$node_response" 2>/dev/null; then
          succeeded_steps=0
          while IFS=$'\t' read -r node_name node_status; do
            [[ -z "$node_name" ]] && continue
            if [[ "$node_status" == "SUCCESS" ]]; then
              succeeded_steps=$((succeeded_steps + 1))
              continue
            fi
            if [[ "$succeeded_steps" -gt 0 ]]; then
              printf '[%s]   ' "$(date '+%Y-%m-%d %H:%M:%S')"
              status_symbol SUCCESS
              printf ' [%s steps succeeded]\n' "$succeeded_steps"
              succeeded_steps=0
            fi
            printf '[%s]   ' "$(date '+%Y-%m-%d %H:%M:%S')"
            status_symbol "$node_status"
            printf ' Step: %s — %s\n' "$node_name" "$node_status"
          done < <(jq -r '.stageFlowNodes[]? | [.name // "(unnamed)", .status // "UNKNOWN"] | @tsv' <<< "$node_response")
          if [[ "$succeeded_steps" -gt 0 ]]; then
            printf '[%s]   ' "$(date '+%Y-%m-%d %H:%M:%S')"
            status_symbol SUCCESS
            printf ' [%s steps succeeded]\n' "$succeeded_steps"
          fi
        fi
      fi
    done < <(jq -r '.stages[]? | [.id // "", .name // "(unnamed)", .status // "UNKNOWN"] | @tsv' <<< "$pipeline_response")
  elif [[ "$PIPELINE_NOTICE_SHOWN" -eq 0 ]]; then
    echo "jenkins-watch: pipeline stage details are unavailable (Pipeline REST API plugin may not be installed); continuing with build status only"
    PIPELINE_NOTICE_SHOWN=1
  fi

  if [[ "$building" == "false" ]]; then
    result=$(jq -r '.result // "unknown result"' <<< "$response")
    printf '[%s] ' "$(date '+%Y-%m-%d %H:%M:%S')"
    status_symbol "$result"
    printf ' Build #%s status: complete (%s)\n' "$build_number" "$result"
    alert -t "Jenkins build complete" "Build #$build_number completed: $result\n$JOB_URL"
    exit 0
  fi

  printf '[%s] ' "$(date '+%Y-%m-%d %H:%M:%S')"
  status_symbol BUILDING
  printf ' Build #%s status: building\n' "$build_number"
  sleep 10
done
