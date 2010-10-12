/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.location;

import std.string;
import std.stdio;


// This was pretty much stolen wholesale from Daniel Keep. <3
struct Location
{
    string filename;
    uint line = 1;
    uint column = 1;
    
    string toString()
    {
        return format("%s(%s:%s)", filename, line, column);
    }
}

char[] readErrorLine(Location loc)
{            
    auto f = File(loc.filename);
    
    foreach(ulong n, char[] line; lines(f)) {
        if(n == loc.line - 1) {
            while(line[$-1] == '\n' || line[$-1] == '\r'){ 
                line = line[0 .. $ - 1];
            }
            return line;
        }
    }
    
    return null;
}