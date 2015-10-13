SDC - The Stupid D Compiler
===========================
This is the home of a [D](http://dlang.org/) compiler.
SDC at the moment implements only a subset of the language and is a work in progress. Please poke around, but do not expect it to compile most code.

This compiler is based on [libd](https://github.com/SDC-developers/SDC/tree/master/libd) for D code analysis. It uses [LLVM](http://llvm.org/) and [libd-llvm](https://github.com/SDC-developers/SDC/tree/master/libd-llvm) for codegen and JIT CTFE. It uses [libsdrt](https://github.com/SDC-developers/SDC/tree/master/libsdrt) to support various runtime facilities required by programs compiled by SDC.

The code is released under the MIT license (see the LICENCE file for more details).
Contact me at deadalnix@gmail.com

SDC requires DMD release `2.068` to compile.

Goals
========
The intent of SDC is to provide a D compiler frontend as a library (libd) in order to improve the overall D toolchain by enabling the possibility of developing new tools.

SDC now supports many very advanced features (static ifs, string mixins, CTFE) of D, but not many basic ones. This is a development choice to allow the architecturing of the compiler around the hardest features of the language. As a consequence, SDC has a solid base to build upon.

What Can It Compile?
====================
See the tests directory for a sample of what is/should-be working.
phobos/object.d contains the current (temporary) object.d file for SDC.

Roadmap
=======
This just me thinking outloud about what features I want, when.

0.1
---
* Compile D style (writeln) hello world.

0.2
---
* Compile itself, which imply compile most of D.

1.0
---
* Propose a stable API for 3rd party.

2.0
---
* extern (C++)


Compiling SDC
=======
You'll need `make`, the latest DMD, and LLVM 3.6 installed.

Run `make`.

Run `make test` to verify that the compiler is working by running the test suite.

SDC contains a lot of hardcoded PATH right now, so it's hard to integrate properly with the system. It expects object.d to be in ../libs/object.d

SDC requires LLVM 3.6 . If the default llvm-config on your system is an older version, you can specify a newer version via `LLVM_CONFIG`. For instance, on a debian system, you want to use `make LLVM_CONFIG=llvm-config-3.6` .

Installing Dependencies on MacOS X
=======
You'll need XCode Tools and the latest DMD installed. You'll also need llvm3.6. One way to install llvm that's been tested is to use [Homebrew](http://brew.sh/). After installing it by following instructions from the web page, run the command `brew install llvm36`, followed by `make LLVM_CONFIG=llvm-config-3.6`.
