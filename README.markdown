SDC - The Stupid D Compiler
===========================
This is the home of a [D2](http://www.digitalmars.com/d/2.0) compiler.
SDC is at the moment, particularly stupid; it is a work in progress. Feel free to poke around, but don't expect it to compile your code.
I don't know what I'm doing in terms of compiler writing. If you find some horrible design decision, that's most likely why.

The code is released under the GPL (see the LICENCE file for more details).
Contact me at b.helyer@gmail.com

Features
========
What follows is a very high level overview of what's done, and what's still to do.
This list is incomplete. SDC is in a state of flux, and this is likely to be out of date.

Lexer
-----
* Scan and handle multiple incoding formats.  _[no -- all code is treated as UTF-8.]_
* Handle BOMs. __[yes.__ -- _anything but UTF-8 is rejected._ __]__
* Handle leading script lines.  _[no.]_
* Split source into tokens.  __[yes.]__
* Replace special tokens.  __[yes.]__
* Process special token sequences.  _[no.]_

Parser
------
* Parse module declarations.  __[yes.]__
* Parse attribute declarations.  __[yes.]__
* Parse import declarations.  __[yes.]__
* Parse enum declarations.  _[partially.]_
* Parse class declarations.  _[no.]_
* Parse interface declarations.  _[no.]_
* Parse aggregate declarations.  _[partially.]_
* Parse declarations.  _[partially.]_
* Parse constructors.  _[no.]_
* Parse destructors.  _[no.]_
* Parse invariants.  _[no.]_
* Parse unittests.  _[no.]_
* Parse static constructors.  _[no.]_
* Parse static destructors.  _[no.]_
* Parse shared static constructors.  _[no.]_
* Parse shared static destructors.  _[no.]_
* Parse conditional declarations.  __[yes.]__
* Parse static asserts.  _[no.]_
* Parse template declarations.  _[partially.]_
* Parse template mixins.  _[no.]_
* Parse mixin declarations.  _[partially.]_
* Parse statements.  _[partially.]_

Codegen
-------
* Import symbols from other modules.  __[yes.]__
* Apply attributes.  _[partially.]_
* Enums.  _[no.]_
* Structs.  _[partially.]_
* Classes.  _[no.]_
* Functions.  _[partially.]_
* Local variables.  _[yes.]_
* Global variables.  _[partially.]_
* Alias declarations.  _[partially.]_
* Expressions.  _[partially.]_
* Label statement.  _[no.]_
* If statement.  __[yes.]__
* While statement.  __[yes.]__
* Do statement.  _[no.]_
* For statement.  _[no.]_
* Switch statement.  _[no.]_
* Final switch statement.  _[no.]_
* Case statement.  _[no.]_
* Case range statement.  _[no.]_
* Default statement.  _[no.]_
* Continue statement.  _[no.]_
* Break statement.  _[no.]_
* Return statement.  _[partially.]_
* Goto statement.  _[no.]_
* With statement.  _[no.]_
* Synchronized statement.  _[no.]_
* Try statement.  _[no.]_
* Scope guard statement.  _[no.]_
* Throw statement.  _[no.]_
* Asm statement.  _[no.]_
* Pragma statement.  _[no.]_
* Mixin statement.  _[yes.]_
* Foreach range statement.  _[no.]_
* Conditional statement.  __[yes.]__
* Static assert.  _[no.]_
* Template mixin.  _[no.]_
* Templated scope. _[partially.]_


What Can It Compile?
====================
Nothing practical. What follows is the a program featuring the most complex features SDC can currently handle.

    module test;

    extern (C) void exit(int);  // extern (D) functions are mangled.

    struct Person
    {
        int age;
        
        void growOlder()
        {
            age = this.age + 1;
        }
    }

    void bump(int* p)
    {
        *p = *p + 1;
        return;
    }

    int add(int a, int b)
    {
        return a + b;
    }

    /**
     * Returns 42.
     */
    int main()
    {
        Person p;
        p.age = 0;
        p.growOlder();
        if (p.age != 1) {
            return 1;
        }
        p.age = p.age + 20;
        int i;
        while (i != 19) {
            i++;
        }
        bump(&i);
        exit(add(p.age, i + 1));
        return 1;  // Never reached.
    }

Roadmap
=======
This just me thinking outloud about what features I want, when.

1.0
---
* druntime compatibility
* phobos compatibility

2.0
---
* dmd calling convention compatibility
* inline assembler

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
