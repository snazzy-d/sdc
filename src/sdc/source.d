/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.source;

import std.file;
import std.utf;
import std.string;

import sdc.compilererror;
import sdc.location;

alias size_t Mark;

/**
 * Class for handling reading of D source code.
 *
 * The class works like a stream, @get and @peek will return the
 * character at @location.
 *
 * Upon loading or getting source the ctor will validate the source
 * code to make sure that it is UTF-8 and the BOM is valid.
 */
class Source
{
    /// Source code, validated UTF-8 by constructors.
    string source;
    /// The location of the current character as returned by @get.
    Location location;
    /// Have we reached EOF, if we have current = dchar.init.
    bool eof = false;
    
    /// The unicode character at @location.
    private dchar mChar;
    /// Index of the next character.
    private size_t mNextIndex;
    /// Index of the current character, used by @save & @sliceFrom.
    private size_t mCurrentIndex;


    /**
     * Open the given file and validate it as a UTF-8 source.
     *
     * Side-effects:
     *   Puts all the other fields into known good states.
     *
     * Throws:
     *   CompilerPanic if source BOM is not valid.
     *   UtfException if source is not UTF-8.
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
    
    /**
     * Sets the source to string and the current location.
     *
     * Throws:
     *   UtfException if the source is not valid UTF-8.
     */
    this(string s, Location location)
    {
        source = s;
        std.utf.validate(source);
        
        get();
        
        this.location = location;
    }
    
    /**
     * Copy contructor, same as @dup.
     */
    this(Source src)
    {
        this.source = src.source;
        this.location = src.location;
        this.eof = src.eof;
        this.mChar = src.mChar;
        this.mNextIndex = src.mNextIndex;
        this.mCurrentIndex = src.mCurrentIndex;
    }

    /**
     * Validate that the current start of source has a valid UTF-8 BOM.
     *
     * Side-effects:
     *   @source advanced to after valid UTF-8 BOM if found.
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

        if (peek != '#' || lookahead(1, lookEOF) != '!')
            return;

        // We have a script line start, read the rest of the line.
        do {
            get();
        } while (peek != '\n' && !eof);
    }

    /**
     * Get the next unicode character.
     *
     * Side-effects:
     *   @eof set to true if we have reached the EOF.
     *   @mChar is set to the returned character if not at EOF.
     *   @mNextIndex advanced to the end of the given character.
     *   @mCurrentIndex is set to @mNextIndex.
     *   @location updated to the current position if not at EOF.
     *
     * Returns:
     *   Returns the unicode char at location or dchar.init at EOF.
     */
    dchar get()
    {
        auto ret = mChar;

        if (mNextIndex >= source.length) {
            eof = true;
            mChar = dchar.init;
            return ret;
        }
        
        if (mChar == '\n') {
            location.line++;
            location.column = 0;
        }
        
        // As UTF-8 chars have different sizes we can't
        // just go mNextIndex - 1 for the previous one.
        mCurrentIndex = mNextIndex;

        // Get the next character.
        mChar = std.utf.decode(source, mNextIndex);
        location.column++;
        
        return ret;
    }
    
    dchar peek() @property
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
        if (n == 0) return peek();
        
        size_t tmpIndex = mNextIndex;
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
        return mCurrentIndex;
    }
    
    string sliceFrom(Mark mark)
    {
        return source[mark .. mCurrentIndex];
    }
    
    /// Make a new Source object in the same state as this one.
    Source dup() @property
    {
        return new Source(this);
    }
    
    /// Synchronise this source with a duplicated one.
    void sync(Source src)
    {
        if (src.source !is this.source) {
            throw new Exception("attempted to sync different sources");
        }
        this.mCurrentIndex = src.mCurrentIndex;
        this.mNextIndex = src.mNextIndex;
        this.mChar = src.mChar;
        this.location = src.location;
        this.eof = src.eof;
    }
}
