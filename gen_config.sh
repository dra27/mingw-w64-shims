#!/bin/sh

set -e

# $1 = name of package
# $2, ... = mingw64 packages to check

package="$1"
shift 1

sysroot_x86_64=''
sysroot_i686=''
gcc=''
packages='-l'

opam_escape='s/\\/\\\\/g;s/%/%%/g;s/"/\\"/g'

for atom in $*; do
  case $atom in
    *-false)
      ;;
    *)
      packages="$packages mingw64-${atom%-true}";;
  esac

  if [ x"${atom#*-}" = 'xgcc-core' ]; then
    arch="${atom%-gcc-core}"

    # The path is fully qualified in order to avoid any existing shims
    gcc="/usr/bin/$arch-w64-mingw32-gcc"

    if command -v -- "$gcc" > /dev/null; then
      case "$arch" in
        x86_64) entry='shim';;
        i686) entry='_shim';;
        *)
          echo "Unsupported or unrecognised architecture: $arch">&2
          exit 2;;
      esac
      sysroot_bin="$("$gcc" -print-sysroot)\\mingw\\bin"
      eval "sysroot_$arch=\
\"\$(cygpath -w \"\$sysroot_bin\" | sed -e '$opam_escape')\""
    else
      echo "$gcc not found" >&2
      exit 1
    fi
  fi
done

if [ -z "$gcc" ]; then
  echo "Neither x86_64-w64-mingw32-gcc nor i686-w64-mingw32-gcc found" >&2
  exit 1
fi

cat > "$package.config" <<EOF
opam-version: "2.0"
variables {
  runtime-x86_64: "$sysroot_x86_64"
  runtime-i686: "$sysroot_i686"
}
EOF

cygwin_root="$(cygpath -w /)"
if [ x"$OPAMROOT\\.cygwin\\root" = x"$cygwin_root" ]; then
  # opam with an internal Cygwin installation - generate a .install file

  "$gcc" "-DCYGWIN_ROOT=$cygwin_root" -DUNICODE -nostdlib -Os \
         -Wl,-entry=$entry -o shim.exe shim.c -lkernel32

  cat > "$package.install" <<"EOF"
bin: [
  "shim.exe" {"cygpath.exe"}
EOF
  for bin in $(cygcheck $packages | grep '^/usr/bin'); do
    bin="${bin##*/}"
    if [ x"${bin%.exe}" != x"$bin" ]; then
      echo "  \"shim.exe\" {\"$bin\"}" >> "$package.install"
    fi
  done
  echo ']' >> "$package.install"
fi
