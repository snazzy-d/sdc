/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */ 
module sdc.source;

import std.file;
import std.utf;
import std.string;

import sdc.location;

alias size_t Mark;

final class Source
{
    string filename;
    string source;
    Location location;
    bool eof = false;
    
    this(string filename)
    {
        this.filename = filename;
        source = cast(string) std.file.read(filename);
        std.utf.validate(source);
        
        get();
        
        location.filename = filename;
        location.line = 1;
        location.column = 1;
    }
    

    dchar get()
    {
        if (mIndex >= source.length) {
            eof = true;
            return dchar.init;
        }
        
        if (mChar == '\n') {
            location.line++;
            location.column = 0;
        }
        
        mChar = std.utf.decode(source, mIndex);
        location.column++;
        
        return mChar;
    }
    
    dchar peek() @property
    {
        return mChar;
    }
        
    dchar lookahead(size_t n, out bool lookaheadEOF)
    {
        lookaheadEOF = false;
        if (n == 0) return peek();
        
        size_t tmpIndex = mIndex;
        foreach (i; 0 .. n) {
            dchar c = std.utf.decode(source, tmpIndex);
            if (tmpIndex >= source.length) {
                lookaheadEOF = true;
                return dchar.init;
            }
            if (i == n - 1) {
                return c;
            }
        }
        assert(false);
    }
    
    Mark save()
    {
        return mIndex - 1;
    }
    
    string sliceFrom(Mark mark)
    {
        return source[mark .. mIndex - 1];
    }

    private dchar mChar;
    private size_t mIndex;
}
