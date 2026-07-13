#!/usr/bin/env bash
filter="grep claude"
if [[ "$1" == "--all" ]]; then
  filter="cat"
fi

gcloud org-policies describe vertexai.allowedModels --project="$ANTHROPIC_VERTEX_PROJECT_ID" --effective \
  | grep 'models/' \
  | if [[ "$1" != "--all" ]]; then grep claude; else cat; fi \
  | sed 's|.*models/||; s|:predict.*||'
