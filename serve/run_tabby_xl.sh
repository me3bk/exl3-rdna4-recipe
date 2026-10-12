#!/bin/bash
# XL profile: MTP head, 160k context. On the current base a full 160k prompt peaks at 14.8 GB (16.24 of 16.3 GB on the
# previous base, which kept per-draft-token DeltaNet history with MTP). EXL3_GDN_REPLAY=0 only matters on the previous
# base. One request at a time: concurrent requests with MTP drafting are untested.
EXL3_GDN_REPLAY=0 exec "$(cd "$(dirname "$0")" && pwd)/run_tabby.sh" \
    --draft-mode mtp --max-seq-len 163840 --cache-size 163840 --max-batch-size 1 "$@"
