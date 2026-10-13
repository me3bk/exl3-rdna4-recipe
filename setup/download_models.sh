#!/bin/bash
# Download the models into models/ (or MODELS_DIR). Uses the `hf` CLI from huggingface_hub (in the venv).
#
#   setup/download_models.sh            main model (3.0 bpw self-calibrated, ~13.4 GB) + the 3.0 bpw DFlash2 draft (0.9 GB)
#   setup/download_models.sh main       main model only
#   setup/download_models.sh draft      the 3.0 bpw DFlash2 draft only (our requant of inco.ai's draft, on Hugging Face)
#   setup/download_models.sh 3.0bpw-plain  turboderp's plain 3.0 bpw quant, the default until 2026-10-09 (13.8 GB)
#   setup/download_models.sh draft-bf16 bf16 DFlash2 draft, to make the 3.0 bpw draft yourself (setup/requant_draft.sh)
#   setup/download_models.sh draft-mia  ready-made 5.0 bpw DFlash2 draft by Mia-AiLab (1.5 GB, no requant needed,
#                                       but it leaves less room for context)
#   setup/download_models.sh 2.5bpw     the 2.5 bpw main model, only for the GPQA/perplexity comparison
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODELS_DIR=${MODELS_DIR:-models}
VENV=${VENV:-$ROOT/.venv}
[ -x "$VENV/bin/hf" ] && export PATH="$VENV/bin:$PATH"
command -v hf >/dev/null || { echo "hf CLI not found; run setup/make_venv.sh first or pip install huggingface_hub" >&2; exit 1; }
cd "$ROOT"

# fetch REPO REVISION DIR: download, then leave .download-complete (the revision) in DIR, so an interrupted download
# isn't mistaken for a finished one (container/run.sh checks it). Rerunning resumes and only fetches what's missing.
fetch() {
    hf download "$1" --revision "$2" --local-dir "$MODELS_DIR/$3"
    echo "$1@$2" > "$MODELS_DIR/$3/.download-complete"
}
main() {
    # Branch SC_3.00bpw_H4 of turboderp's repo: self-calibrated 3.0 bpw with a 4-bit head (pinned to the tested commit)
    fetch turboderp/Qwen3.8-27B-exl3 86b95530f9d365d90dd24d01a997a8de0cdf6c55 Qwen3.8-27B-EXL3-SC3.0bpw-H4
}
main_plain() {
    # Branch 3.00bpw (commit 6fe61ad620abfe97c5b49f9722c2bceeea4ccc28 when tested)
    hf download turboderp/Qwen3.8-27B-exl3 --revision 3.00bpw --local-dir "$MODELS_DIR/Qwen3.8-27B-EXL3-3.0bpw"
}
draft() {
    # setup/requant_draft.sh's output for incoai/Qwen3.8-27B-DFlash2 at 015e795, byte-identical to what we run
    fetch parth-thakre/Qwen3.8-27B-DFlash2-EXL3-3.0bpw 3d915b126ceecdb3ce41587ca19faa782a91fee0 Qwen3.8-27B-DFlash2-EXL3-3.0bpw
}
draft_bf16() {
    # The DFlash2 draft (inco.ai / z-lab, Apache-2.0; mirrored at z-lab/Qwen3.8-27B-DFlash2), at the revision we converted
    hf download incoai/Qwen3.8-27B-DFlash2 --revision 015e795645c74b1a0eeef3b570031fb62e769bc5 \
        --local-dir "$MODELS_DIR/Qwen3.8-27B-DFlash2-bf16"
}
draft_mia() {
    hf download Mia-AiLab/Qwen3.8-27B-DFlash2-EXL3-5.0bpw --local-dir "$MODELS_DIR/Qwen3.8-27B-DFlash2-EXL3-5.0bpw"
}
main_25() {
    # Branch 2.50bpw (commit 0cd1091272291d008e06976acb81e25946cdc767 when tested)
    hf download turboderp/Qwen3.8-27B-exl3 --revision 2.50bpw --local-dir "$MODELS_DIR/Qwen3.8-27B-EXL3-2.5bpw"
}

case ${1:-default} in
    default)    main; draft ;;
    main)       main ;;
    draft)      draft ;;
    3.0bpw-plain) main_plain ;;
    draft-bf16) draft_bf16 ;;
    draft-mia)  draft_mia ;;
    2.5bpw)     main_25 ;;
    *) echo "usage: $0 [main|draft|3.0bpw-plain|draft-bf16|draft-mia|2.5bpw]" >&2; exit 2 ;;
esac
