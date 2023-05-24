# SDC - The Snazzy D Compiler

This is the home of a [D][0] compiler. SDC is at the moment, particularly
stupid; it is a work in progress. Feel free to poke around, but don't expect it
to compile your code.

The project currently provides a collection of tools:

- [sdc][1], the D compiler.
- [sdunit][2], an utility to run the unit tests in D modules.
- [sdfmt][3], a code formatter for D.

This compiler is based on [libd][4] for D code analysis. It uses [LLVM][5] and
[libd-llvm][6] for codegen and JIT CTFE. It uses [libsdrt][7] to support various
runtime facilities required by programs compiled by SDC.

The code is released under the MIT license (see the LICENCE file for more
details). Contact me at deadalnix@gmail.com.

SDC requires latest DMD release to compile.

[0]: http://dlang.org/
[1]: https://github.com/snazzy-d/sdc/blob/master/src/driver/sdc.d
[2]: https://github.com/snazzy-d/sdc/blob/master/src/driver/sdunit.d
[3]: https://github.com/snazzy-d/sdc/blob/master/src/driver/sdfmt.d
[4]: https://github.com/snazzy-d/sdc/tree/master/src/d
[5]: http://llvm.org/
[6]: https://github.com/snazzy-d/sdc/tree/master/src/d/llvm
[7]: https://github.com/snazzy-d/sdc/tree/master/sdlib

# Goals

Right now, SDC is a work in progress and unusable for any production work. Its
intent is to provide a D compiler as a library (libd) in order to improve the
overall D toolchain by enabling the possibility of developing new tools.

SDC now supports many very advanced features (static ifs, string mixins, CTFE)
of D, but not many basic ones. This is a development choice to allow the
architecturing of the compiler around the hardest features of the language. As a
consequence, SDC has a solid base to build upon.

# What Can It Compile?

See the [tests directory][20] for a sample of what is/should-be working. You can
also build [SDC's runtime library][21], that is compiled using SDC.

[20]: https://github.com/snazzy-d/sdc/tree/master/test
[21]: https://github.com/snazzy-d/sdc/tree/master/sdlib

# Compiling SDC on Linux

You'll need `make` and the latest DMD installed and LLVM 15.

Run `make`.

Then you can run the test suite using `make check`. There should be no
regressions.

SDC requires a recent version of LLVM. If the default llvm-config on your system
is too old, you can specify a newer version via `LLVM_CONFIG`. For instance, on
a debian system, you want to use `LLVM_CONFIG=llvm-config-11 make` .

# Compiling SDC on Mac OS X

You'll need `make` and the latest DMD installed. You'll also need a recent
version of LLVM if you don't already have it. One way to install llvm that's
been tested is to use [Homebrew][40], a package manager for OS X. After
installing it by following instructions from the web page, run the command
`brew install llvm11`, followed by `LLVM_CONFIG=llvm-config-11 make` . If you
are using [MacPorts][41] instead, you can run `sudo port install llvm-11`,
followed by `LLVM_CONFIG=llvm-config-mp-11 make` . You'll also need a recent
version of `nasm`; if `nasm` does not recognise the `macho64` output format, try
upgrading `nasm` to a newer version.

[40]: http://brew.sh/
[41]: http://www.macports.org

# Building SDC as a Nix package

On Linux, you can also use the [Nix package manager][50] to automatically fetch
dependencies and build SDC for you. You may need to use the unstable nix
channel, to have a new enough `dmd` to build SDC. Clone or download this
repository.

To build the executable, run
`nix-build -E "(import <nixpkgs> {}).callPackage ./. {}"` or
`nix-build -E "(import <nixpkgs> {}).callPackage ./. {dflags=\"-O -release\";}"`
from the project root directory.

[50]: https://nixos.org
