/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.compilererror;

import std.stdio;
import std.string;

import sdc.location;

enum ErrorType
{
    Compilation,
    Other
}

class CompilerError : Exception
{
    Location location;
    bool hasLocation = false;
    
    ErrorType type = ErrorType.Compilation;
    
    this(string message, ErrorType type = ErrorType.Compilation)
    {
        if(type == ErrorType.Compilation) {
            super(format("error: %s", message));
        } else {
            super(message);
        }
        this.type = type;
    }
    
    this(Location loc, string message)
    {
        super(format("%s: error: %s", loc, message));
        location = loc;
        hasLocation = true;
    }
    
    char[] readLine()
    {
        if(!hasLocation)
            throw new Exception("CompilerError has no location");
            
        auto f = File(location.filename);
        foreach(ulong lineNumber, char[] line; lines(f))
        {
            if(lineNumber == location.line - 1)
                return line;
        }
        
        return null;
    }
}

void errorMessageOnly(Location loc, string message)
{
    stderr.writeln(format("%s: error: %s", loc, message));
}

void warning(Location loc, string message)
{
    stderr.writeln(format("%s: warning: %s", loc, message));
}
