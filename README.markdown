SDC - The Stupid D Compiler
===========================
This is the home of a [D](http://d-programming-language.org/) compiler.
SDC is at the moment, particularly stupid; it is a work in progress. Feel free to poke around, but don't expect it to compile your code.
I don't know what I'm doing in terms of compiler writing. If you find some horrible design decision, that's most likely why.

The code is released under the MIT license (see the LICENCE file for more details).
Contact me at b.helyer@gmail.com

Last tested with: DMD release `2.059` in May, 2012.

Features
========
What follows is a very high level overview of what's done, and what's still to do.
This list is incomplete. SDC is in a state of flux, and this is likely to be out of date.

Lexer
-----
* Scan and handle multiple encoding formats.  __[yes.]__ 
* Handle leading script lines.  __[yes.]__
* Split source into tokens.  __[yes.]__
* Replace special tokens.  __[yes.]__
* Process special token sequences.  __[yes.]__

Parser
------
* Parse module declarations.  __[yes.]__
* Parse attribute declarations.  __[yes.]__
* Parse import declarations.  __[yes.]__
* Parse enum declarations.  __[yes.]__
* Parse class declarations.  _[partially.]_
* Parse interface declarations.  _[no.]_
* Parse aggregate declarations.  _[partially.]_
* Parse declarations.  _[partially.]_
* Parse constructors.  __[yes.]__
* Parse destructors.  __[yes.]__
* Parse invariants.  _[no.]_
* Parse unittests.  __[yes.]__
* Parse static constructors.  __[yes.]__
* Parse static destructors.  __[yes.]__
* Parse shared static constructors.  __[yes.]__
* Parse shared static destructors.  __[yes.]__
* Parse conditional declarations.  __[yes.]__
* Parse static asserts.  __[yes.]__
* Parse template declarations.  _[partially.]_
* Parse template mixins.  _[no.]_
* Parse mixin declarations.  _[partially.]_
* Parse statements.  _[partially.]_

Codegen
-------
* Import symbols from other modules.  __[yes.]__
* Apply attributes.  _[partially.]_
* Enums.  __[yes.]__
* Structs.  _[partially.]_
* Classes.  _[partially.]_
* Functions.  _[partially.]_
* Overloaded functions. __[yes.]__
* Function pointers. __[yes.]__
* Local variables.  __[yes.]__
* Global variables.  __[yes.]__
* Alias declarations.  _[partially.]_
* Expressions.  _[partially.]_
* Label statement.  __[yes.]__
* If statement.  __[yes.]__
* While statement.  __[yes.]__
* Do statement.  __[yes.]__
* For statement.  __[yes.]__
* Switch statement.  _[no.]_
* Final switch statement.  _[no.]_
* Case statement.  _[no.]_
* Case range statement.  _[no.]_
* Default statement.  _[no.]_
* Continue statement.  _[no.]_
* Break statement.  _[no.]_
* Return statement.  __[yes.]__
* Goto statement.  _[partially.]_
* With statement.  _[no.]_
* Synchronized statement.  _[no.]_
* Try statement.  _[no.]_
* Scope guard statement.  _[no.]_
* Throw statement.  _[no.]_
* Asm statement.  _[no.]_
* Pragma statement.  _[no.]_
* Mixin statement.  _[yes.]_
* Foreach range statement.  __[yes.]__
* Conditional statement.  __[yes.]__
* Static assert.  __[yes.]__
* Template mixin.  _[no.]_
* Templated scope. _[partially.]_


What Can It Compile?
====================
See the tests directory for a sample of what is/should-be working.
libs/object.d contains the current (temporary) object.d file for SDC.  

Roadmap
=======
This just me thinking outloud about what features I want, when.

0.1
---
* druntime compiles

0.2
---
* phobos compiles

0.3
---
* inline assembler

1.0
---
* dmd calling convention compatibility
* self hosting

2.0
---
* extern (C++)


Compiling SDC on Linux
=======
You'll need make and the latest DMD installed.
Install LLVM 3.0.
Run `make`.
Copy `bin/sdc` into your `$PATH` somewhere.
You'll need to create a file, either `/etc/sdc.conf` or `~/.sdc.conf` (the latter may change to `~/.local/share/sdc/sdc.conf` at some point, so be warned) with contents like so:

    {
        "defaultImportPaths":["~/path/to/SDC/libs"],
        "defaultFlags":["-m64", "--debug"]
    }

The last bit is optional, but SDC needs to know where to find `object.d` is the point.
Then you can compile `runner.d` with `dmd` and run it to run the test suites. There will be a handful of failures, but the majority (> 95%) should pass. 

SDC with DMD/Windows
=======
(These instructions are from Jakob, so please don't contact me regarding them.)

The following are required for LLVM to function on Windows:

* [LLVM](http://llvm.org/) >= 3.0
  * SDC requires the core libraries as a DLL, and the `llc` and `opt` tools
* [MinGW](http://www.mingw.org/)
  * SDC requires `gcc`, as well as GNU `make` for the makefile

~~~A copy of `llvm-2.9.dll` and `llvm-2.9.lib` in DMD-compatible OMF format can be downloaded from [here](https://github.com/downloads/JakobOvrum/SDC/llvm-2.9-Win32-DLL.rar) for convenience.~~~
The above have not been updated for LLVM 3.0, unfortunately. Until then, you'll have to convert it with `implib` or so. Good luck! -B.

For the LLVM tools, grab "LLVM Binaries for Mingw32/x86" on the [LLVM download page](http://llvm.org/releases/download.html).
### Setup
Extract the LLVM DLL binary archive to the SDC repository, then build with `make -f Makefile.windows`.
When running SDC, make sure `gcc`, `llc` and `opt` are available in your PATH.

To run the tests, execute `dmd runner.d` to build the test-runner application found in `tests/`, then run it with `runner`.
