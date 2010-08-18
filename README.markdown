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
This list is incomplete.

Lexer
-----
* Scan and handle multiple incoding formats.  _[no -- all code is treated as UTF-8 format at the moment.]_
* Handle leading script lines.  _[no.]_
* Split source into tokens.  __[yes.]__
* Replace special tokens.  __[yes.]__
* Process special token sequences.  _[no.]_

Parser
------
* Parse module declarations.  __[yes.]__
* Parse attribute declarations.  __[yes.]__
* Parse import declarations.  __[yes.]__
* Parse enum declarations.  _[no.]_
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
* Parse template declarations.  _[no.]_
* Parse template mixins.  _[no.]_
* Parse mixin declarations.  _[no.]_
* Parse statements.  _[partially.]_

Codegen
-------
* Import symbols from other modules.  _[no.]_
* Apply attributes.  _[no.]_
* Enums.  _[no.]_
* Structs.  _[no.]_
* Classes.  _[no.]_
* Functions.  _[partially.]_
* Local variables.  _[partially.]_
* Global variables.  _[no.]_
* Alias declarations.  __[yes.]__
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
* Mixin statement.  _[no.]_
* Foreach range statement.  _[no.]_
* Conditional statement.  __[yes.]__
* Static assert.  _[no.]_
* Template mixin.  _[no.]_


What Can It Compile?
====================
Nothing practical. What follows is the a program featuring most complex features SDC can currently handle.
By 'handle', I mean can compile a working executable, and featured features act as expected.

    module test;  // The name given here is currently ignored.
    extern (C):   // Only C mangling (or lack thereof) and call conventions are currently supported.
    
    version = foo;
    
    int add(int a, int b)
    {
        return a + b;
    }
    
    version (none) int foo() { return 12; }
    
    /++
     + Returns: the value '42'.
     +/
    int main()
    {
        bool b;
        int i = cast(int)b + 1, j = 38;  // No implicit casting.
        i++;
        while (j == 38) {
            if (i == 2) j++;
        }
        version (foo) j++;
        version (all) j--;
        version (none) j++;
        return add(++j, i);
    }
