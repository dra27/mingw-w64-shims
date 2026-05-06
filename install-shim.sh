#!/bin/sh

set -e

# install-shim.sh <package> <cygwin-package-list> <bindir> handles the creation
# of shim executables for opam-managed Cygwin installations. When installed in
# a switch which has an opam-managed Cygwin installation, it creates
# <package>.install which duplicates the existing cygpath.exe in <bindir> to
# shim the executables named in the packages in <cygwin-package-list>. A
# package calling this script must depend on either conf-mingw-w64-gcc-i686 or
# conf-mingw-w64-gcc-x86_64 in order to ensure that the cygpath.exe shim has
# already been installed.
# The script supports three additional arguments which are used for
# conf-mingw-w64-gcc-{i686,x86_64} only: <cc> <shim-fn> [<shim>] which specify
# the name of the C compiler and the mangled name of the entry point in shim.c.
# These are used to compile shim.c (in this mode of operation, <bindir> is
# ignored). This shim is then used to shim the executables in
# <cygwin-package-list> and, if included, the executable <shim>.exe.
# In this mode, install-shim.sh also creates <package>.config, setting the
# runtime variable for the package to the runtime binary directory under the
# path returned by <cc> -print-sysroot, converted to a Windows path.
# <package>.config is created for both opam-managed and user-managed Cygwin
# installations.

package="$1"
cygwin_packages="$2"
switch_bin="$3"
# The path is fully qualified in order to avoid any existing shims
gcc="${4:+/usr/bin/$4}"
entry="$5"
shim="${6:+$6.exe}"

sysroot=''
opam_escape='s/\\/\\\\/g;s/%/%%/g;s/"/\\"/g'

if [ -n "$gcc" ]; then
  if command -v -- "$gcc" > /dev/null; then
    sysroot="$(cygpath -w "$("$gcc" -print-sysroot)/mingw/bin" | \
               sed -e "$opam_escape")"
  else
    echo "$gcc not found" >&2
    exit 1
  fi

  cat > "$package.config" <<EOF
opam-version: "2.0"
variables {
  runtime: "$sysroot"
}
EOF
fi

cygwin_pkg_mgr="$(opam --cli=2.2 option sys-pkg-manager-cmd | \
                  sed -e 's/\] \[/]\n[/g' | \
                  sed -ne 's/\]\+$//;/^\[\?\["cygwin"/s/\[*"cygwin" //p')"
if [ -n "$cygwin_pkg_mgr" ]; then
  # opam with a managed Cygwin PATH (i.e. opam adds this Cygwin's bin
  # directory when building packages). In this case shims are required and
  # we generate a .install file.
  if [ -n "$entry" ]; then
    "$gcc" "-DCYGWIN_ROOT=$(cygpath -w /)" -DUNICODE -nostdlib -Os \
           -Wl,-entry=$entry -o shim.exe shim.c -lkernel32
  else
    cp "$switch_bin/cygpath.exe" 'shim.exe'
  fi
  {
    echo 'bin: ['
    if [ -n "$shim" ]; then
      echo "  \"shim.exe\" {\"$shim\"}"
    fi
    for bin in $(cygcheck -l $cygwin_packages | grep '^/usr/bin'); do
      bin="${bin##*/}"
      if [ x"${bin%.exe}" != x"$bin" ]; then
        echo "  \"shim.exe\" {\"$bin\"}"
      fi
    done
    echo ']'
  } > "$package.install"
fi
