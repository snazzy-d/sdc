/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */
module sdc.location;

import std.string;


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
