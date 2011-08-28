/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.source;

import std.file;
import std.utf;
import std.string;

import sdc.compilererror;
import sdc.location;

alias size_t Mark;

class Source
{
    string source;
    Location location;
    bool eof = false;
    
    /**
     * Open the given file and validate it as a utf8 source.
     *
     * Side-effects:
     *   Puts all the other fields into known good states.
     *
     * Throws:
     *   CompilerPanic if source BOM is not valid.
     *   UtfException if source is not utf8.
     */
    this(string filename)
    {
        source = cast(string) std.file.read(filename);
        checkBOM();
        std.utf.validate(source);        
        get();
        skipScriptLine();
        
        location.filename = filename;
        location.line = 1;
        location.column = 1;
    }
    
    this() {}
    
    /**
     * Sets the source to string and the current location.
     *
     * Throws:
     *   UtfException if the source is not valid utf8.
     */
    this(string s, Location location)
    {
        source = s;
        std.utf.validate(source);
        
        get();
        
        this.location = location;
    }
    
    /**
     * Validate that the current start of source has a valid utf8 BOM.
     *
     * Side-effects:
     *   @source advanced to after valid utf8 BOM if found.
     *
     * Throws:
     *   CompilerPanic if source if BOM is not valid.
     */
    void checkBOM()
    {
        if (source.length >= 2 && source[0 .. 2] == [0xFE, 0xFF] ||
            source.length >= 2 && source[0 .. 2] == [0xFF, 0xFE] ||
            source.length >= 4 && source[0 .. 4] == [0x00, 0x00, 0xFE, 0xFF] ||
            source.length >= 4 && source[0 .. 4] == [0xFF, 0xFE, 0x00, 0x00]) {
            
            throw new CompilerPanic("only UTF-8 input is supported.");
        }
        if (source.length >= 3 && source[0 .. 3] == [0xEF, 0xBB, 0xBF]) {
            source = source[3 .. $];
        }
    }
    
    /**
     * Used to skip the first script line in D sources.
     */
    void skipScriptLine()
    {
        bool lookEOF = false;

        if (mChar != '#' || lookahead(1, lookEOF) != '!')
            return;

        // We have a script line start, read the rest of the line.
        while (get() != '\n' && !eof) {}
    }

    /**
     * Get the next unicode character.
     *
     * Side-effects:
     *   @eof set to true if we have reached the EOF.
     *   @mChar is set to the returned character if not at EOF.
     *   @mIndex advanced to the end of the given character.
     *   @location updated to the current position if not at EOF.
     *
     * Returns:
     *   Returns next unicode char or dchar.init at EOF.
     */
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
    
    dchar current() @property
    {
        return mChar;
    }

    /**
     * Return the unicode character @n chars forwards.
     *
     * Side-effects:
     *   @lookaheadEOF set to true if we reached EOF, otherwise false.
     *
     * Returns:
     *   Unicode char at @n or dchar.init at EOF.
     */
    dchar lookahead(size_t n, out bool lookaheadEOF)
    {
        if (n == 0) return mChar;
        
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
