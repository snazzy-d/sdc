SDC - The Stupid D Compiler
===========================
This is the home of a [D2](http://www.digitalmars.com/d/2.0) compiler.
SDC is at the moment, particularly stupid; it is a work in progress. Feel free to poke around, but don't expect it to compile your code.
I don't know what I'm doing in terms of compiler writing. If you find some horrible design decision, that's most likely why.

The code is released under the GPL (see the LICENCE file for more details).
Contact me at b.helyer@gmail.com

SDC with DMD/Windows
=======
(These instructions are from Jakob, so please don't contact me regarding them.)

The following are required for LLVM to function on Windows:

* [LLVM](http://llvm.org/) >= 2.7
  * SDC requires the `llc` tool as well as the LLVM core libraries
* [MinGW](http://www.mingw.org/)
  * SDC requires `gcc`

A copy of `llvm-2.8.dll`, `llvm-2.8.lib` and `llc.exe` can be downloaded from [here](http://filesmelt.com/dl/llvm-2.8-Win32-bin_.zip) for convenience.

### Setup
Compile all source files in `sdc/import` and `sdc/src` to produce `sdc.exe`, the compiler driver. SDC uses the LLVM C API, so you need to link with LLVM (the included `llvm-2.8.lib` will work). Once successfully compiled and linked, make sure `sdc.exe`, LLVM's `llc.exe` and MinGW's `gcc.exe` can be found in your system PATH.

Simply execute `dmd runner.d` to build the test-runner application found in `compiler_tests/`, then run it with `runner`.
