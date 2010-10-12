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
    Location location;
    bool hasLocation = false;
    
    this(string message)
    {
        super(format(errorFormat(), message));
    }
    
    this(Location loc, string message)
    {
        super(format(locationFormat(), loc, message));
        location = loc;
        hasLocation = true;
    }
    
    protected:
    string errorFormat()
    {
        return "error: %s";
    }
    
    string locationFormat()
    {
        return "%s: error: %s";
    }
}

class CompilerPanic : CompilerError
{
    this(string message)
    {
        super(message);
    }
    
    this(Location loc, string message)
    {
        super(loc, message);
    }
    
    protected override:
    string errorFormat()
    {
        return "panic: %s";
    }
    
    string locationFormat()
    {
        return "%s: panic: %s";
    }
}

char[] readErrorLine(Location loc)
{            
    auto f = File(loc.filename);
    
    foreach(ulong n, char[] line; lines(f)) {
        if(n == loc.line - 1) {
            return line;
        }
    }
    
    return null;
}

void errorMessageOnly(Location loc, string message)
{
    stderr.writeln(format("%s: error: %s", loc, message));
}

void warning(Location loc, string message)
{
    stderr.writeln(format("%s: warning: %s", loc, message));
}