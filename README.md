# Cygwin Shims Generator

Cygwin, like any other Unix system, installs executables to global binary
directories (`/usr/bin`). It is useful to be able to export specific binaries
from `bin` to the Command Processor and PowerShell, but without exporting the
entire `bin` directory.

This project provides a tiny C launcher which can be used to create shim
executables for invoking Cygwin programs. It sets up the environment to allow
them to be called without realising that they are not running from a Cygwin
shell.

These shims can be put in a different directory which can be added to
PATH, allowing them to be used without pulling in the whole of Cygwin's
bin directory.

# Compilation

See `gen_config.sh`. The shim executable is compiled with:

```console
$ x86_64-w64-mingw32-gcc '-DCYGWIN_ROOT=C:\cygwin64' -DUNICODE -nostdlib -Os \
                         -Wl,-entry=shim -o shim.exe shim.c -lkernel32
```

(if compiling for 32-bit, the entry point will be `_shim`)

`shim.exe` can then be renamed or copied and, when run, will attempt to execute
its own basename from the `bin` directory under `CYGWIN_ROOT`, passing all the
same arguments except that the first argument (i.e. `argv[0]`) will be
rewritten to the correct executable path.

Note that while `shim.exe` can be hard-linked to new names, symlinks fail since
Cygwin's resolution of basename causes the file to have the wrong basename when
invoked from within a Cygwin shell (i.e. a symlinked executable will work
_outside_ Cygwin, but not inside it).

# opam package

`gen_config.sh` is intended for use in [opam-repository][], but it compiles
shim.c and generates opam .config and .install files.

The mingw-w64-shims package requires one of the mingw-w64 C compilers and uses
`cygcheck` to install a copy of `shim.exe` for each binary installed by the
mingw-w64 packages which are wrapped in opam-repository.

The package also ensure that the mingw-w64 runtime bin directory is added to
PATH.

[opam-repository]: https://github.com/ocaml/opam-repository
