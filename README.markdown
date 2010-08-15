SDC - The Stupid D Compiler
===========================

This is the home of a [D2](http://www.digitalmars.com/d/2.0) compiler.
SDC is at the moment, particularly stupid; it is a work in progress. Feel free to poke around, but don't expect it to compile your code.
I don't know what I'm doing in terms of compiler writing. If you find some horrible design decision, that's most likely why.

The code is released under the GPL (see the LICENCE file for more details).
Contact me at b.helyer@gmail.com


Features
========

Lexer
-----
* Scan and handle multiple incoding formats.  _[no -- all code is treated as UTF-8 format at the moment.]_
* Handle leading script lines.  _[no.]_
* Split source into tokens.  *_[yes.]_*
* Replace special tokens.  *_[yes.]_*
* Process special token sequences.  _[no.]_

Parser
------
* Parse module declaration.  *_[yes.]_*
* Parse attribute declarations.  *_[yes.]_*
* Parse import declarations.  *_[yes.]_*


Codegen
-------


Roadmap
=======
