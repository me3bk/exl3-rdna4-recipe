#!/bin/bash
# Long profile: draft with the model's built-in MTP head instead of DFlash2 (no draft model; peak 14.1 GB at a 127.8k
# prompt), 128k context. DeltaNet replay is upstream's and always on (EXL3_GDN_REPLAY=0 here only matters on the
# previous base, which had no replay with MTP). One request at a time: 3 slots fit (14.7 GB at 127.8k), but concurrent
# requests with MTP drafting are untested.
EXL3_GDN_REPLAY=0 exec "$(cd "$(dirname "$0")" && pwd)/run_tabby.sh" \
    --draft-mode mtp --max-seq-len 131072 --cache-size 131072 --max-batch-size 1 "$@"
