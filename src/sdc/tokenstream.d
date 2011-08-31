/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.tokenstream;

import std.stdio;
import std.string;

import sdc.compilererror;
public import sdc.token;


/**
 * A stream of tokens, produced by @TokenWriter.
 */
class TokenStream
{
    /// The filename that this source was taken from.
    string filename;
    
    /// All the tokens in this stream.
    private Token[] mTokens;
    /// Pointing to the current token as returned by @peek and @getToken.
    private size_t mIndex;


    /**
     * Construct a new token stream with a given filename and token array.
     *
     * The internal pointer is set to the start of the stream. Also validates
     * the stream is long enough and is started and terminated correctly.
     *
     * Throws:
     *   CompilerPanic if array is malformed.
     */
    this(string filename, Token[] tokens)
    {
        if (tokens.length < 3)
            throw new CompilerPanic("Token stream too short.");
        if (tokens[0].type != TokenType.Begin)
            throw new CompilerPanic("Token stream not started correctly.");
        if (tokens[$-1].type != TokenType.End)
            throw new CompilerPanic("Token stream not terminated correctly.");

        this.filename = filename;
        this.mTokens = tokens;
    }
    
    /**
     * Return the current token and advance the internal counter.
     *
     * Side-effects:
     *   Internal pointer is incremented to the next token.
     */
    Token get()
    {
        auto retval = mTokens[mIndex];
        if (mIndex < mTokens.length - 1) {
            mIndex++;
        }
        return retval;
    }
    
    /**
     * Return the current token.
     */
    Token peek() @property
    {
        return mTokens[mIndex];
    }
    
    /**
     * Return the previous token.
     *
     * Throws:
     *   CompilerPanic if accessing before the first token.
     */
    Token previous() @property
    {
        if (mIndex < 1)
            throw new CompilerPanic("Token array out of bounds access.");
        return mTokens[mIndex - 1];
    }
    
    /**
     * Return the token at @n steps before the current token.
     * If @n is 0 the function is the same as @peek.
     *
     * Throws:
     *   CompilerPanic if accessing before the first token.
     */
    Token lookahead(size_t n)
    {
        if (n == 0) {
            return peek();
        }
        auto index = mIndex + n;
        if (index >= mTokens.length) {
            return mTokens[$-1];
        }
        
        return mTokens[index];
    }
    
    /**
     * Return the token at @n steps behind the current token.
     * If @n is 0 the function is the same as @peek.
     *
     * Throws:
     *   CompilerPanic if accessing before the first token.
     */
    Token lookbehind(size_t n)
    {
        auto index = mIndex - n;
        if (index < 0)
            throw new CompilerPanic("Token array out of bounds access.");
        return mTokens[mIndex - n];
    }
    
    void printTo(File file)
    {
        foreach (t; mTokens) {
            file.writefln("%s (%s @ %s)", t.value, tokenToString[t.type], t.location);
        }
    }
}
