SDC - The Stupid D Compiler
===========================
This is the home of a [D](http://dlang.org/) compiler.
SDC is at the moment, particularly stupid; it is a work in progress. Feel free to poke around, but don't expect it to compile your code.

This compiler is based on [libd](https://github.com/deadalnix/libd) for D code analysis. It uses [LLVM](http://llvm.org/) and [libd-llvm](https://github.com/deadalnix/libd-llvm) for codegen and JIT CTFE.

The code is released under the MIT license (see the LICENCE file for more details).
Contact me at deadalnix@gmail.com

SDC require DMD release `2.067` to compile.

Goals
========
Right now, SDC is a work in progress and unusable for any production work. It intends to provide a D compiler as a library (libd) in order to improve overall D toolchain by enabling the possibility of develloping new tools.

SDC now support many very advanced feature of (static ifs, string mixins, CTFE) but not many basic ones. This is a devellopement choice to allow the architecturing of the compiler around the hardest features of the language. As a consequence, SDC is a solid base to build upon.

What Can It Compile?
====================
See the tests directory for a sample of what is/should-be working.
libs/object.d contains the current (temporary) object.d file for SDC.  

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


Compiling SDC on Linux
=======
You'll need `make` and the latest DMD installed.
Install LLVM 3.5.

Run `make`.

Then you can compile `runner.d` with `dmd` and run it to run the test suites. There should be no regressions.
SDC contains le lot of hardcoded PATH right now, so it hard to integrate properly with the system. It expect object.d to be in ../libs/object.d

SDC require LLVM 3.5 . if the default llvm-config on your system is an older version, you can specify a newer version via `LLVM_CONFIG`. For instance, on a debian system, you want to use `make LLVM_CONFIG=llvm-config-3.5` .

### Setup
Extract the LLVM DLL binary archive to the SDC repository, then build with `make -f Makefile.windows`.
When running SDC, make sure `gcc`, `llc` and `opt` are available in your PATH.

To run the tests, execute `dmd runner.d` to build the test-runner application found in `tests/`, then run it with `runner`.
