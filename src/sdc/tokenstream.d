/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */ 
module sdc.tokenstream;

import std.stdio;
import std.string;

import sdc.source;
import sdc.compilererror;
public import sdc.token;


final class TokenStream
{
    Source source;
    string filename;
    
    this() {}  // TMP
    this(Source source)
    {
        this.source = source;
        auto start = new Token();
        start.type = TokenType.Begin;
        start.value = "START";
        mTokens ~= start;
    }
    
    void addToken(Token token)
    {
        mTokens ~= token;
    }
    
    Token lastAdded() @property
    {
        return mTokens[$ - 1];
    }
    
    Token getToken()
    {
        auto retval = mTokens[mIndex];
        if (mIndex < mTokens.length - 1) {
            mIndex++;
        }
        return retval;
    }
    
    Token peek() @property
    {
        return mTokens[mIndex];
    }
    
    private Token[] mTokens;
    private size_t mIndex;
}
