/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.compilererror;

import std.stdio;
import std.string;

import sdc.location;


class CompilerError : Exception
{
    this()
    {
        super("CompilerError");
    }
}

void error(string message)
{
    stderr.writeln(format("error: %s", message));
    throw new CompilerError();
}

void error(Location loc, string message)
{
    stderr.writeln(format("%s: error: %s", loc, message));
    throw new CompilerError();
}

void errorMessageOnly(Location loc, string message)
{
    stderr.writeln(format("%s: error: %s", loc, message));
}

void warning(Location loc, string message)
{
    stderr.writeln(format("%s: warning: %s", loc, message));
}

void panic(Location loc, string message)
{
    stderr.writeln(format("%s: Internal Compiler Error: %s", loc, message));
    throw new CompilerError();
}

void panic(string message)
{
    stderr.writeln(format("Internal Compiler Error: %s", message));
    throw new CompilerError();
}
