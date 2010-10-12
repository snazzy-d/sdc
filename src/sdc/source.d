/**
 * Copyright 2010 SDC Authors. See AUTHORS for more details.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.source;

import std.file;
import std.utf;
import std.string;

import sdc.location;

alias size_t Mark;

class Source
{
    string source;
    Location location;
    bool eof = false;
    
    this(string filename)
    {
        source = cast(string) std.file.read(filename);
        std.utf.validate(source);
        
        get();
        
        location.filename = filename;
        location.line = 1;
        location.column = 1;
    }
    this() {}
    

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
    
    /// Make a new Source object in the same state as this one.
    Source dup() @property
    {
        auto newSource = new Source();
        newSource.source = this.source;
        newSource.location = this.location;
        newSource.eof = this.eof;
        newSource.mChar = this.mChar;
        newSource.mIndex = this.mIndex;
        return newSource;
    }
    
    /// Synchronise this source with a duplicated one.
    void sync(Source src)
    {
        if (src.source !is this.source) {
            throw new Exception("attempted to sync different sources");
        }
        this.location = src.location;
        this.mIndex = src.mIndex;
        this.mChar = src.mChar;
        this.eof = src.eof;
    }

    private dchar mChar;
    private size_t mIndex;
}
