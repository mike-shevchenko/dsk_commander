#!/bin/bash

# Builds DISK Commander from the source tree that holds this script into the sibling directory
# of its name and "-build": with the MSVC of the newest Visual Studio and a Qt 6 for MSVC 2022 on
# Windows (MSYS2 or Git Bash), with the system compiler and Qt elsewhere. QT_DIR names the Qt to
# use, the directory holding lib/cmake; on Windows the newest one in C:/Qt/ is the default.
#
# Usage: build.sh [cmake-option...]
#
# The options go to the CMake configuration, as -DDC_LTO=OFF. BUILD_DIR=... builds elsewhere.

set -o pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# The compiler needs the environment of vcvars64.bat, which only cmd takes in, so a batch file
# in the build directory configures and builds; Visual Studio brings CMake and Ninja too.
build_msvc() {
  local src_dir="$1"
  local build_dir="$2"
  shift 2
  local vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
  local vs_dir
  vs_dir="$("${vswhere}" -latest -property installationPath)" && [[ -n "${vs_dir}" ]] \
      || fail "No Visual Studio found."
  local bat="${build_dir}/build.bat"
  cat > "${bat}" <<EOF
@set "PATH=$(cygpath -w "$(dirname "${vswhere}")");%PATH%"
@call "$(cygpath -w "${vs_dir}/VC/Auxiliary/Build/vcvars64.bat")" >nul || exit /b 1
cmake -S "$(cygpath -w "${src_dir}")" -B "$(cygpath -w "${build_dir}")" -G Ninja $* || exit /b 1
cmake --build "$(cygpath -w "${build_dir}")" -j $(nproc) || exit /b 1
EOF
  # cmd.exe itself: MSYS2's cmd is a wrapper that needs COMSPEC, which a login shell lacks
  cmd.exe //c "$(cygpath -w "${bat}")" || fail "The build failed."
}

build_native() {
  local src_dir="$1"
  local build_dir="$2"
  shift 2
  command -v cmake > /dev/null || fail "No cmake found."
  local -a generator=()
  if command -v ninja > /dev/null; then
    generator=(-G Ninja)
  fi
  cmake -S "${src_dir}" -B "${build_dir}" "${generator[@]}" "$@" \
      || fail "The configuration failed; if it found no Qt, set QT_DIR to the Qt to use."
  cmake --build "${build_dir}" -j "$(nproc)" || fail "The build failed."
}

main() {
  local src_dir
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" \
      || fail "Cannot locate the source tree."
  local build_dir="${BUILD_DIR:-${src_dir}-build}"
  local windows=false
  case "$(uname -o)" in
    Msys|Cygwin) windows=true ;;
  esac

  local qt_dir="${QT_DIR}"
  if "${windows}"; then
    if [[ -z "${qt_dir}" ]]; then
      qt_dir="$(printf '%s\n' /c/Qt/6.*/msvc2022_64 | sort -V | tail -n 1)"
      [[ -d "${qt_dir}" ]] || fail "No Qt 6 for MSVC 2022 in C:/Qt/: install one, or set" \
          "QT_DIR to the directory of the Qt to use, as C:/Qt/6.11.2/msvc2022_64."
    fi
    [[ -d "${qt_dir}" ]] || fail "QT_DIR names no directory: ${QT_DIR}"
    qt_dir="$(cygpath -m "${qt_dir}")"
  fi
  local -a options=(-DCMAKE_BUILD_TYPE=Release)
  if [[ -n "${qt_dir}" ]]; then
    options+=("-DCMAKE_PREFIX_PATH=${qt_dir}")
  fi
  options+=("$@")

  mkdir -p "${build_dir}" || fail "Cannot create ${build_dir}/."
  echo "Building ${src_dir}/ in ${build_dir}/ with Qt ${qt_dir:-of the system}"
  if "${windows}"; then
    build_msvc "${src_dir}/src" "${build_dir}" "${options[@]}"
  else
    build_native "${src_dir}/src" "${build_dir}" "${options[@]}"
  fi
}

main "$@"
