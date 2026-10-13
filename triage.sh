#!/bin/bash
# Something didn't work? This collects what an AI coding agent needs to help (distro, kernel, GPU and device access,
# container runtime, recipe version, the last server and build logs) and opens the first agent CLI you have installed
# (Claude Code, Codex or OpenCode) with it, in this directory. The agent sends it to its model provider, like
# anything you type into it; tokens and keys are removed first, and in a terminal you're asked before it opens.
#
#   ./triage.sh                       collect and open an agent
#   ./triage.sh "what went wrong"     add your own description or the error message
#   AGENT=codex ./triage.sh           pick the agent (claude, codex or opencode)
#   OpenCode uses one of its free models (OPENCODE_MODEL=provider/model to pick, OPENCODE_MODEL=keep for your default)
#   ./triage.sh --print               only write the prompt file and print its path (paste it into any assistant)
set -uo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
print_only=false
[ "${1:-}" = --print ] && { print_only=true; shift; }
problem=${*:-}

# Tokens and keys: long hex strings, common token prefixes, key/password/secret/token values in key: value,
# key=value and "key": "value" form, and Bearer headers. Applied to the whole prompt, your own text included.
redact() {
    sed -E 's/[0-9a-fA-F]{32,}/<redacted>/g
        s/(hf_|sk-|sk_|ghp_|gho_|ghs_|github_pat_|xox[abp]-|glpat-|AKIA)[A-Za-z0-9_-]{8,}/<redacted>/g
        s/("?[A-Za-z_]*(api[_-]?key|token|secret|password|passwd)[A-Za-z_]*"?[[:space:]]*[:=][[:space:]]*)("[^"]*"|[^[:space:],}]+)/\1<redacted>/Ig
        s/(Bearer)[[:space:]]+[^[:space:]"]+/\1 <redacted>/Ig'
}
section() { printf '\n### %s\n```\n' "$1"; }
endsec() { printf '```\n'; }
run() { "$@" 2>&1 | head -n "${LINES_MAX:-40}"; }

collect() {
    section "System"
    . /etc/os-release 2>/dev/null; echo "distro: ${PRETTY_NAME:-unknown}"
    echo "kernel: $(uname -r)"
    echo "recipe: $(git rev-parse --short HEAD 2>/dev/null || echo 'not a git checkout') $(git status --porcelain 2>/dev/null | grep -q . && echo '(local changes)')"
    echo "RAM: $(free -g 2>/dev/null | awk '/^Mem:/{print $2 " GB total, " $7 " GB available"}')"
    echo "disk: $(df -h . 2>/dev/null | awk 'NR==2{print $4 " free here"}')"
    endsec
    section "GPU"
    run lspci -nn 2>/dev/null | grep -iE 'vga|display|3d' || echo "lspci not available"
    lsmod 2>/dev/null | grep -q '^amdgpu' && echo "amdgpu module: loaded" || echo "amdgpu module: NOT loaded"
    ls -l /dev/kfd /dev/dri/renderD* 2>&1
    echo "you: $(id)"
    command -v amd-smi >/dev/null && run amd-smi metric --mem-usage 2>/dev/null | grep -E 'GPU|VRAM'
    command -v hipconfig >/dev/null && echo "hipconfig: $(hipconfig --version 2>/dev/null)" || echo "hipconfig: not installed (fine for the container)"
    endsec
    section "Container runtime"
    for ct in docker podman; do
        if command -v $ct >/dev/null; then
            echo "$ct: $($ct --version 2>&1)"
            $ct info >/dev/null 2>&1 && echo "  $ct info: ok" || echo "  $ct info: FAILS ($($ct info 2>&1 | tail -1))"
            $ct ps -a --filter name=exl3-rdna4 --format '  container {{.Names}}: {{.Status}} ({{.Image}})' 2>/dev/null
        else
            echo "$ct: not installed"
        fi
    done
    endsec
    for ct in docker podman; do
        if command -v $ct >/dev/null && $ct ps -a -q --filter name=exl3-rdna4 2>/dev/null | grep -q .; then
            section "Container log ($ct logs --tail 80 exl3-rdna4)"
            $ct logs --tail 80 exl3-rdna4 2>&1 | redact
            endsec
        fi
    done
    if [ -d .venv ] || [ -d exllamav3 ] || [ -d logs ]; then
        section "Host install"
        echo "venv: $([ -x .venv/bin/python ] && .venv/bin/python -c 'import sys, torch; print(sys.version.split()[0], "torch", torch.__version__)' 2>&1 | tail -1 || echo missing)"
        echo "exllamav3 checkout: $([ -d exllamav3 ] && git -C exllamav3 rev-parse --short HEAD 2>/dev/null || echo missing)"
        echo "built extension: $(ls exllamav3/exllamav3_ext*.so 2>/dev/null || echo none)"
        echo "models: $(ls models 2>/dev/null | tr '\n' ' ')"
        endsec
        [ -f logs/tabby.log ] && { section "Server log (logs/tabby.log, last 80 lines)"; tail -n 80 logs/tabby.log | redact; endsec; }
        [ -f logs/build_exllamav3.log ] && {
            section "Build log (logs/build_exllamav3.log: errors, then the last 30 lines)"
            grep -aE 'error|Error|fatal' logs/build_exllamav3.log | head -20 | redact
            echo ...; tail -n 30 logs/build_exllamav3.log | redact
            endsec
        }
    fi
}

prompt_file=$(mktemp "${TMPDIR:-/tmp}/exl3-rdna4-triage.XXXXXX.md")
raw=$(mktemp)
{
cat <<EOF
I'm trying to run exl3-rdna4-recipe (Qwen3.8-27B with ExLlamaV3 + TabbyAPI on an AMD RX 9070 / 9070 XT) and something
isn't working. You're in the recipe's directory. Please help me get it running.

What went wrong, in my words: ${problem:-"(not given; work it out from the details below)"}

How to help:
- Start from the details below, then read README.md, container/README.md (the container route) and the
  "Limitations" in notes/measurements.md. The setup scripts are in setup/, the container files in container/.
- Explain what you think is wrong before changing anything, and ask before anything that needs sudo, installs
  packages, or deletes files (never delete downloaded models or the .venv without asking).
- Don't post anything online for me. If it looks like a bug in the recipe, write a GitHub issue I can review and file
  myself at https://github.com/parth-thakre/exl3-rdna4-recipe/issues, with the details that matter.

Details collected by ./triage.sh on $(date -u '+%Y-%m-%d %H:%M UTC'):
EOF
collect
} > "$raw"
redact < "$raw" > "$prompt_file"
rm -f "$raw"

if $print_only; then echo "$prompt_file"; exit 0; fi

fallback() {
    echo "The details are in: $prompt_file"
    echo "Paste that file into any AI assistant, or attach it to an issue at https://github.com/parth-thakre/exl3-rdna4-recipe/issues"
    exit "${1:-0}"
}

agents=(claude codex opencode)
[ -n "${AGENT:-}" ] && agents=("$AGENT")
for a in "${agents[@]}"; do
    command -v "$a" >/dev/null || continue
    if [ -t 0 ] && [ -t 1 ]; then
        echo "The details are in $prompt_file (keys and tokens removed; have a look if you like)."
        read -r -p "Open $a with them? It sends them to $a's model provider. [Y/n] " ans || ans=n
        case $ans in [nN]*) fallback ;; esac
    fi
    p=$(cat "$prompt_file")
    case $a in
        claude|codex) exec "$a" "$p" ;;
        opencode)
            # A free model by default, so this needs no paid model or API key of your own. OpenCode's free lineup changes,
            # so take big-pickle (its own free model) if it's offered, else the first opencode/*-free one.
            m=${OPENCODE_MODEL:-}
            if [ -z "$m" ]; then
                list=$(timeout 30 opencode models 2>/dev/null || true)
                m=$(grep -x 'opencode/big-pickle' <<<"$list" || grep -m1 -E '^opencode/.*-free$' <<<"$list" || true)
                # Not silently your own default, which may be a paid model
                [ -n "$m" ] || { echo "No free OpenCode model found; set OPENCODE_MODEL=provider/model (or =keep for your default)."; fallback 1; }
            fi
            if [ "$m" != keep ]; then
                [[ $m =~ ^[A-Za-z0-9._:/#-]+$ ]] || { echo "OPENCODE_MODEL doesn't look like provider/model: $m" >&2; exit 2; }
                echo "OpenCode model: $m"
                export OPENCODE_CONFIG_CONTENT="{\"model\": \"$m\"}"
            fi
            exec opencode --prompt "$p" ;;
        *)            echo "AGENT must be claude, codex or opencode" >&2; exit 2 ;;
    esac
done
echo "No agent CLI found (claude, codex or opencode)."
fallback
