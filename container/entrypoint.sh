#!/bin/bash
# Container entrypoint: check the models are mounted, then start TabbyAPI through serve/run_tabby.sh (same environment
# as a host install). Arguments go to TabbyAPI, e.g. --config /path/to/config.yml or --max-batch-size 2. CTX=128k
# (docker run -e CTX=128k) serves 128k context instead of the default 96k.
# Defaults (container/config.yml): models in /models, port 8096, no API key (the container is meant to sit behind a
# gateway or a port published on 127.0.0.1 only).
#   entrypoint.sh download   download both models into /models instead (mount it writable; container/run.sh does this)
set -euo pipefail
cd /opt/recipe
M=${EXL3_MODELS:-/models}
if [ "${1:-}" = download ]; then
    export PATH="/opt/recipe/.venv/bin:$PATH"
    exec env MODELS_DIR="$M" setup/download_models.sh
fi
config=tabbyAPI/config.yml
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case ${args[i]} in
        --config=*) config=${args[i]#--config=} ;;
        --config) [ $((i + 1)) -lt ${#args[@]} ] || { echo "entrypoint: --config needs a path" >&2; exit 2; }
                  config=${args[i + 1]} ;;
    esac
done

missing=()
for d in Qwen3.8-27B-EXL3-SC3.0bpw-H4 Qwen3.8-27B-DFlash2-EXL3-3.0bpw; do
    # Only the default layout is checked; a config that names other models is taken as is. The models may come from
    # anywhere (run.sh, the local-ai plugin, by hand), so this looks for config.json, not a download marker.
    if [ "$config" = tabbyAPI/config.yml ] && [ ! -f "$M/$d/config.json" ]; then missing+=("$d"); fi
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "entrypoint: missing in $M: ${missing[*]}" >&2
    echo "  Mount a directory with both models at $M (container/README.md has the download commands)." >&2
    exit 1
fi

exec serve/run_tabby.sh "$@"
