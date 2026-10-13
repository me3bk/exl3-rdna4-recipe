# Find the system ROCm. Sourced by env.sh, build_exllamav3.sh, fetch_deps.sh and kernels/build.sh; safe to source from an
# interactive shell (it never exits, and works with or without set -u). find_rocm sets ROCM_PATH and ROCM_HOME (same
# value), ROCM_CLANG_DIR (the directory with ROCm's clang and clang++) and ROCM_HIPCC. Distros differ: AMD's packages
# (Ubuntu, Debian, RHEL, SUSE) and Arch install under /opt/rocm, Fedora under /usr with clang in /usr/lib64/rocm/llvm/bin.
# `hipconfig` knows both, so it is asked when nothing is set. To pick one of several installs, set ROCM_PATH (e.g.
# /opt/rocm-7.2.0); its own tools are then preferred, and ROCM_CLANG_DIR can be set too.

# _rocm_same DIR1 DIR2: both name the same directory (/opt/rocm is often a symlink to /opt/rocm-7.x)
_rocm_same() {
    [ -n "$1" ] && [ -n "$2" ] && [ "$(cd "$1" 2>/dev/null && pwd -P)" = "$(cd "$2" 2>/dev/null && pwd -P)" ]
}

# _rocm_ask HIPCONFIG ARG...: hipconfig's answer without surrounding whitespace
_rocm_ask() {
    local v
    v=$("$@" 2>/dev/null) || return 1
    v=${v#"${v%%[![:space:]]*}"}
    printf '%s' "${v%"${v##*[![:space:]]}"}"
}

_rocm_has_clang() { [ -x "$1/clang" ] && [ -x "$1/clang++" ]; }

find_rocm() {
    local root=${ROCM_PATH:-${ROCM_HOME:-}} hc= dir cand
    # No root requested: ask hipconfig (PATH, then AMD's default location), then try the usual places
    if [ -z "$root" ]; then
        for cand in "$(command -v hipconfig 2>/dev/null)" /opt/rocm/bin/hipconfig; do
            [ -n "$cand" ] && [ -x "$cand" ] || continue
            root=$(_rocm_ask "$cand" --rocmpath) && [ -n "$root" ] && { hc=$cand; break; }
            root=
        done
    fi
    if [ -z "$root" ]; then
        for dir in /opt/rocm /usr; do
            [ -e "$dir/include/hip/hip_runtime.h" ] && { root=$dir; break; }
        done
    fi
    if [ -z "$root" ] || [ ! -e "$root/include/hip/hip_runtime.h" ]; then
        echo "setup/rocm.sh: no ROCm found (looked for include/hip/hip_runtime.h under ${root:-/opt/rocm and /usr})." >&2
        echo "  Install your distro's ROCm HIP SDK (README.md, Requirements) or set ROCM_PATH." >&2
        return 1
    fi

    # Tools from the same install: its own hipconfig, or one on PATH only if it reports this root (asked with the ROCm
    # variables cleared, since hipconfig echoes ROCM_PATH back)
    if [ -z "$hc" ]; then
        if [ -x "$root/bin/hipconfig" ]; then
            hc=$root/bin/hipconfig
        else
            cand=$(command -v hipconfig 2>/dev/null) || cand=
            if [ -n "$cand" ] && _rocm_same "$(_rocm_ask env -u ROCM_PATH -u ROCM_HOME -u HIP_PATH "$cand" --rocmpath)" "$root"; then
                hc=$cand
            fi
        fi
    fi
    # A ROCM_CLANG_DIR the user set is used as is (and must be valid). One this function set earlier (e.g. env.sh
    # against another install) is detected afresh.
    local clang_dir=${ROCM_CLANG_DIR:-} auto=
    [ -n "$clang_dir" ] && [ "$clang_dir" = "${_ROCM_CLANG_AUTO:-}" ] && clang_dir=
    if [ -n "$clang_dir" ]; then
        if ! _rocm_has_clang "$clang_dir"; then
            echo "setup/rocm.sh: ROCM_CLANG_DIR=$clang_dir has no clang and clang++" >&2
            return 1
        fi
    else
        auto=1
        if [ -n "$hc" ]; then
            clang_dir=$(_rocm_ask "$hc" --hipclangpath) || clang_dir=
        fi
        if [ -z "$clang_dir" ] || ! _rocm_has_clang "$clang_dir"; then
            clang_dir=
            for dir in "$root/llvm/bin" "$root/lib/llvm/bin"; do
                _rocm_has_clang "$dir" && { clang_dir=$dir; break; }
            done
            # Fedora: ROCm in /usr, its clang in /usr/lib64/rocm/llvm
            if [ -z "$clang_dir" ] && _rocm_same "$root" /usr && _rocm_has_clang /usr/lib64/rocm/llvm/bin; then
                clang_dir=/usr/lib64/rocm/llvm/bin
            fi
        fi
    fi
    if [ -z "$clang_dir" ]; then
        echo "setup/rocm.sh: found ROCm at $root but not its clang++; set ROCM_CLANG_DIR" >&2
        return 1
    fi

    ROCM_PATH=$root ROCM_HOME=$root ROCM_CLANG_DIR=$clang_dir ROCM_HIPCC=$root/bin/hipcc
    if [ -n "$auto" ]; then _ROCM_CLANG_AUTO=$clang_dir; else _ROCM_CLANG_AUTO=; fi
    export ROCM_PATH ROCM_HOME ROCM_CLANG_DIR ROCM_HIPCC _ROCM_CLANG_AUTO
}
