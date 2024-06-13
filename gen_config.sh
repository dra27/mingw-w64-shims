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
    pkgconf)
      # Most of the packages need to be prefixed 'mingw64-', the ones which
      # don't are explicitly listed here
      packages="$packages $atom";;
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

cygwin_pkg_mgr="$(opam --cli=2.2 option sys-pkg-manager-cmd | \
                  sed -e 's/\] \[/]\n[/g' | \
                  sed -ne 's/\]\+$//;/^\[\?\["cygwin"/s/\[*"cygwin" //p')"
if [ -n "$cygwin_pkg_mgr" ]; then
  # opam with a managed Cygwin PATH (i.e. opam adds this Cygwin's bin
  # directory when building packages). In this case shims are required and
  # we generate a .install file.

  cygwin_root="$(cygpath -w /)"

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
