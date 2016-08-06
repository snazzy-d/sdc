# SDC Architecture

# Purpose

The purpose of this document is to provide a high level overview of the constructs which make up the SDC compiler.  Additionally, we will discuss how flows through, and is transformed by the compiler.

# Data Flow within the compiler

Character Streams -> Lexer -> (Token Stream) -> Parser -> (AST) -> Semantic Pass -> (SDIR) -> Code Gen -> (LLVM IR) -> LLVM -> (Machine Code)

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

#### Locations + Errors
	+ Another nice feature is that SDC threads location data throughout the ast and ir so that the compiler can generate errors telling the user precisely where the mistake was made!

## Semantic Pass (incl. Scheduler)
	+ Operates on the Ast provided by the parser to generate SDIR.  Is started at the root each module being compiled.
	+ Scheduler provides arbitrary look-ahead without needing to use continuation-passing style through the use of fibers (effectively coroutines)
	+ Allows for type inference.
	+ May reduce some higher level Ast concepts into easier concepts to express in the IR.
	+ *** Need to cover visitors, and require, scheduler, etc.
	+ Cover how visitors work -- Equivalent to functional programming concept of parameter specialization

### SDIR 

## Code Generation
	+ Operates on the IR produced by the semantic pass

## Runtime (libsdrt)
	+ Some of the features implemented in the D programming languages are best implemented through a library.  This library is called the runtime, and the compiler emits references to symbols which are expected to be resolved by the linker.  The runtime library makes up the allocator, gc, and various other low level language features.
