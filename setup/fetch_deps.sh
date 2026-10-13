#!/bin/bash
# Check that the headers the exllamav3 build (and Triton at runtime) needs are installed, and say how to get the missing
# ones. On Fedora it can also fetch them without sudo: the -devel packages are downloaded and unpacked into deps/usr,
# which setup/env.sh and setup/build_exllamav3.sh add to CPATH. Elsewhere it prints the install command for your distro.
#
# Environment overrides:
#   ROCM_PATH          ROCm install to check (default: found by setup/rocm.sh)
#   PYTHON             interpreter the venv will use, for Python.h (default: python3.12, as in setup/make_venv.sh)
#   DEPS_DIR           where to unpack (default: deps/)
#   NO_FETCH=1         only check, even on Fedora
#
# Versions on the test machine (Fedora 44): hipblaslt-devel 7.1.1-7, hipcub-devel 7.1.0-5, hiprand-devel 7.1.0-6,
# hipsolver-devel 7.1.0-5, hipsparse-devel 7.1.1-5, hipsparselt-devel 7.1.1-4, python3.12-devel 3.12.15-1,
# rocm-smi-devel 7.1.1-3, rocprim-devel 7.1.1-3, rocsolver-devel 7.1.1-4, rocsparse-devel 7.1.0-6,
# rocthrust-devel 7.1.1-3.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/setup/rocm.sh"
DEPS_DIR=${DEPS_DIR:-$ROOT/deps}
PYTHON=${PYTHON:-python3.12}

find_rocm || exit 1
echo "ROCm: $ROCM_PATH (clang in $ROCM_CLANG_DIR)"

# header | Fedora package | Debian/Ubuntu package (AMD's repo) | Arch package
HEADERS="
hip/hip_runtime.h            rocm-hip-devel       hip-dev          hip-runtime-amd
rocblas/rocblas.h            rocblas-devel        rocblas-dev      rocblas
hipblas/hipblas.h            hipblas-devel        hipblas-dev      hipblas
hipblas-common/hipblas-common.h hipblas-common-devel hipblas-common-dev hipblas-common
hipblaslt/hipblaslt.h        hipblaslt-devel      hipblaslt-dev    hipblaslt
hipcub/hipcub.hpp            hipcub-devel         hipcub-dev       hipcub
hiprand/hiprand.h            hiprand-devel        hiprand-dev      hiprand
rocrand/rocrand.h            rocrand-devel        rocrand-dev      rocrand
hipsolver/hipsolver.h        hipsolver-devel      hipsolver-dev    hipsolver
hipsparse/hipsparse.h        hipsparse-devel      hipsparse-dev    hipsparse
hipsparselt/hipsparselt.h    hipsparselt-devel    hipsparselt-dev  hipsparselt
rocm_smi/rocm_smi.h          rocm-smi-devel       rocm-smi-lib     rocm-smi-lib
rocprim/rocprim.hpp          rocprim-devel        rocprim-dev      rocprim
rocsolver/rocsolver.h        rocsolver-devel      rocsolver-dev    rocsolver
rocsparse/rocsparse.h        rocsparse-devel      rocsparse-dev    rocsparse
thrust/version.h             rocthrust-devel      rocthrust-dev    rocthrust
"

have_header() {
    local d
    for d in "$ROCM_PATH/include" /usr/include "$DEPS_DIR/usr/include"; do
        [ -e "$d/$1" ] && return 0
    done
    return 1
}

# The distro family from /etc/os-release: fedora, debian or arch. Anything else gets the package lists for all three.
# RHEL and its rebuilds say ID_LIKE=fedora but use AMD's packages (other names, /opt/rocm), so they count as other.
family=other
if [ -r /etc/os-release ]; then
    for id in $(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}"); do
        case $id in
            rhel|centos|rocky|almalinux|ol) family=other; break ;;
            fedora) family=fedora; break ;;
            debian|ubuntu) family=debian; break ;;
            arch) family=arch; break ;;
        esac
    done
fi

missing_hdr=() missing_fedora=() missing_debian=() missing_arch=()
while read -r hdr fed deb arch; do
    [ -n "$hdr" ] || continue
    if ! have_header "$hdr"; then
        missing_hdr+=("$hdr"); missing_fedora+=("$fed"); missing_debian+=("$deb"); missing_arch+=("$arch")
    fi
done <<< "$HEADERS"

# Python.h for the interpreter the venv uses (Triton compiles a C helper against it at runtime)
if command -v "$PYTHON" >/dev/null; then
    pyinc=$("$PYTHON" -c 'import sysconfig; print(sysconfig.get_paths()["include"])')
    pyver=$("$PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
    if [ ! -e "$pyinc/Python.h" ] && [ ! -e "$DEPS_DIR/usr/include/python$pyver/Python.h" ]; then
        missing_hdr+=("python$pyver/Python.h"); missing_fedora+=("python$pyver-devel")
        missing_debian+=("python$pyver-dev"); missing_arch+=("python")
    fi
else
    echo "warning: $PYTHON not found, so Python.h wasn't checked (setup/make_venv.sh needs it; README.md, Requirements)" >&2
fi

if [ ${#missing_hdr[@]} -eq 0 ]; then
    echo "all headers present, nothing to fetch"
    exit 0
fi
echo "missing headers: ${missing_hdr[*]}"

if [ "$family" = fedora ] && [ "${NO_FETCH:-0}" != 1 ] && command -v dnf >/dev/null; then
    for tool in rpm2cpio cpio; do
        command -v "$tool" >/dev/null || { echo "missing $tool; install it or the packages: sudo dnf install ${missing_fedora[*]}" >&2; exit 1; }
    done
    echo "fetching without sudo into $DEPS_DIR (or: sudo dnf install ${missing_fedora[*]})"
    mkdir -p "$DEPS_DIR/rpms"
    dnf download --arch x86_64 --arch noarch --destdir "$DEPS_DIR/rpms" "${missing_fedora[@]}"
    cd "$DEPS_DIR"
    for rpm in rpms/*.rpm; do
        echo "unpacking $(basename "$rpm")"
        # Through a file, not a pipe: cpio stops at the archive trailer, and with pipefail rpm2cpio's SIGPIPE aborts the loop
        rpm2cpio "$rpm" > payload.cpio
        cpio -idm --quiet < payload.cpio
    done
    rm -f payload.cpio
    echo "headers in $DEPS_DIR/usr/include (setup/env.sh and setup/build_exllamav3.sh add it to CPATH)"
    exit 0
fi

echo "install them, then rerun this script:"
case $family in
    fedora) echo "  sudo dnf install ${missing_fedora[*]}" ;;
    debian) echo "  sudo apt install ${missing_debian[*]}"
            echo "  (from AMD's ROCm apt repository; the distro's own ROCm packages are too old)" ;;
    arch)   echo "  sudo pacman -S --needed $(printf '%s\n' "${missing_arch[@]}" | sort -u | tr '\n' ' ')" ;;
    *)      echo "  Fedora:        ${missing_fedora[*]}"
            echo "  Debian/Ubuntu: ${missing_debian[*]}"
            echo "  Arch:          ${missing_arch[*]}" ;;
esac
exit 1
