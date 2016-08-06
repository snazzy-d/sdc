# SDC Architecture

# Purpose

The purpose of this document is to provide a high level overview of the constructs which make up the SDC compiler.  Additionally, we will discuss how flows through, and is transformed by the compiler.

# Constructs

## Lexer
	+ Made up of some maps, and some CTFE produces a string mixin of the actual lexer.  It ends up being made out of nested switches and is thus relatively fast.
	+ Takes character stream and breaks it up into tokens of the appropriate types

## Parser
	+ Takes Token stream and produces an abstract syntax tree made up of Statements and Expressions. 

### Statements
	+ Anything can make up a line of code.

#### Expressions
	+ A type of statement which has a type associated with it.

##### Types
	+ Qualifiers
	+ Type info
	+ Provides a way to tell if an expression is assignable to another identifier.

## Semantic Pass (incl. Scheduler)
	+ Operates on the Ast provided by the parser to generate an IR.
	+ Provides arbitrary look-ahead without needing to use continuation-passing style.
	+ Allows for type inference, 
	+ Trampoline but no need for continuation-passing style
	+ Fibers

##### Locations + Errors
	+ Another nice feature is that SDC threads location data throughout the ast and ir so that the compiler can generate errors telling the user precisely where the mistake was made!