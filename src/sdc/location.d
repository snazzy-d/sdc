/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2011 Jakob Ovrum.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.location;

import std.string;
import std.stdio;


/**
 * Struct representing a location in a source file.
 *
 * This was pretty much stolen wholesale from Daniel Keep. <3
 */
struct Location
{
    string filename;
    size_t line = 1;
    size_t column = 1;
    size_t length = 0;
    
    string toString() const
    {
        return format("%s(%s:%s)", filename, line, column);
    }
    
    // Difference between two locations
    // end - begin == begin ... end
    Location opBinary(string op)(ref const Location begin) const if (op == "-") in {
        assert(begin.filename == filename);
        assert(begin.line <= line);
    } body {
        Location loc;
        loc.filename = filename;
        loc.line = begin.line;
        loc.column = begin.column;
        
        if (line != begin.line) {
            loc.length = -1; // End of line
        } else {
            assert(begin.column <= column);
            loc.length = column + length - begin.column;
        }
        
        return loc;
    }
    
    void spanTo(ref const Location end)
    {
        if (line <= end.line && column < end.column) {
            this = end - this;
        }
    }
    
    // When the column is 0, the whole line is assumed to be the location
    immutable size_t wholeLine = 0;
}

char[] readErrorLine(Location loc)
{            
    auto f = File(loc.filename);
    
    foreach(ulong n, char[] line; lines(f)) {
        if (n == loc.line - 1) {
            while(line.length && (line[$-1] == '\n' || line[$-1] == '\r')) {
                line = line[0 .. $ - 1];
            }
            return line;
        }
    }
    
    return null;
}
