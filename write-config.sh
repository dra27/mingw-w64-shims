#!/bin/sh

set -e

# write-config.sh <package> [<config_1> ... <config_n>] creates <package>.config
# <config_x> is either a file, which is checksum'd and added to file-depends, or
# -v which introduces a variable where the following argument is its name, which
# can be decorated with a type (string, bool, or list). Following that is the
# value which is either a string, true or false, or a list, where the entries
# are delimited with the first argument, e.g.
#   -v s foo
#     => s: "foo"
#   -v s:string bar
#     => s: "bar"
#   -v b:bool true
#     => b: true
#   -v l:list bracket elt1 elt2 bracket
#     => l: ["elt1" "elt2"]

checksum() {
  # SHA512 > SHA256 > MD5 (obviously) using GNU coreutils (shaXXXsum),
  # Perl's Digest::SHA (shasum), or BSD (shaXXX)
  if command -v sha512sum >/dev/null; then
    h="$(sha512sum "$1" | cut -d' ' -f1)"
    a='sha512'
  elif command -v shasum >/dev/null; then
    h="$(shasum -a 512 "$1" | cut -d' ' -f1)"
    a='sha512'
  elif command -v sha512 >/dev/null; then
    h="$(sha512 -q "$1")"
    a='sha512'
  elif command -v sha256sum >/dev/null; then
    h="$(sha256sum "$1" | cut -d' ' -f1)"
    a='sha256'
  elif command -v sha256 >/dev/null; then
    h="$(sha256 -q "$1")"
    a='sha256'
  elif command -v md5sum >/dev/null; then
    h="$(md5sum "$1" | cut -d' ' -f1)"
    a='md5'
  elif command -v md5 >/dev/null; then
    h="$(md5 -q "$1")"
    a='md5'
  else
    echo "No tool found to compute hash of $1" >&2
    return 1
  fi
  if test -z "$h"; then
    echo "Error computing $a hash of $1" >&2
    return 1
  fi
  echo "$a=$h"
}

package="$1"

if test -z "$package"; then
  echo "No package name specified" >&2
  exit 1
fi

shift 1

rm -f "$package.config-files" "$package.config-vars"

escape='s/\\/\\\\/g;s/%/%%/g;s/"/\\"/g;s/.*/"&"/'
while test $# -gt 0; do
  case "$1" in
    -v)
      var_name="${2%%:*}"
      var_type="${2#*:}"
      test x"$var_type" != x"$2" || var_type='string'
      if test -z "$var_name"; then
        echo 'No variable name supplied for -v' >&2
        exit 1
      fi
      if test $# -lt 3; then
        echo "No value supplied for $var_name" >&2
        exit 1
      fi
      var_value="$3"
      case "$var_type" in
        string)
          cat > "$package.config-list" <<EOF
$var_value

EOF
          shift 3;;
        bool)
          case "$var_value" in
            true|false)
              echo "  $var_name: $var_value" >> "$package.config-vars";;
            *)
              echo "Invalid boolean value for $var_name: $var_value" >&2
              exit 1;;
          esac
          shift 3;;
        list)
          if test -z "$var_value"; then
            echo "Missing list terminator" >&2
            exit 1
          fi
          shift 3
          var_type='empty'
          {
            test x"$1" = x"$var_value" && echo ''
            while true; do
              if test $# -eq 0; then
                echo "End of arguments encountered before list terminated" >&2
                exit 1
              fi
            cat <<EOF
$1
EOF
              test x"$1" != x"$var_value" || break
              shift 1
              case "$var_type" in
                empty) var_type='string';;
                string) var_type='list';;
              esac
            done
          } > "$package.config-list"
          shift 1;;
        *)
          echo "Invalid type for $var_name: $var_type" >&2
          exit 1;;
      esac
      if test -e "$package.config-list"; then
        var_value="$(sed -e '$d;'"$escape" "$package.config-list" \
                       | paste -s -d ' ' -)"
        case "$var_type" in
          list) var_value="[$var_value]";;
        esac
        rm -f "$package.config-list"
        cat >> "$package.config-vars" <<EOF
  $var_name: $var_value
EOF
      fi;;
    *)
      if test -e "$1"; then
        h="$(checksum "$1")" || exit 1
      else
        h='00000000000000000000000000000000'
      fi
      cat > "$package.config-list" <<EOF
$1
EOF
      cat >> "$package.config-files" <<EOF
  [$(sed -e "$escape" "$package.config-list") "$h"]
EOF
      rm -f "$package.config-list"
      shift 1;;
  esac
done

{
  echo 'opam-version: "2.0"'
  if test -e "$package.config-files"; then
    echo 'file-depends: ['
    cat "$package.config-files"
    echo ']'
    rm -f "$package.config-files"
  fi
  if test -e "$package.config-vars"; then
    echo 'variables {'
    cat "$package.config-vars"
    echo '}'
  fi
  rm -f "$package.config-vars"
} > "$package.config"
