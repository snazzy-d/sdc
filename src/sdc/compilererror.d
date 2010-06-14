/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.compilererror;

import std.stdio;
import std.string;

import sdc.location;


class CompilerError
{
}

void error(Location loc, string message)
{
    stderr.writeln(format("%s: error: %s.", loc, message));
    throw new CompilerError();
}

void warning(Location loc, string message)
{
    stderr.writeln(format("%s: warning: %s.", loc, message));
}
