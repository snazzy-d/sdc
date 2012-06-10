/**
 * Copyright 2012 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 * 
 * External interface to the SDC compiler.
 */
module sdc.compiler;

import sdc.lexer;
import sdc.source;
import sdc.tokenstream;
import sdc.ast.sdcmodule;
import sdc.parser.base;


/**
 * Encapsulates a compiler instance. 
 * Analagous to a single command line invocation.
 */
class Compiler
{
    /**
     * Adds a file to the list of files to be compiled.
     * Throws: UtfException if source is not valid unicode.
     * Returns: the ID of the source file. This is used as its
     *          position in related function calls that return IDs.
     */
    size_t addSource(string filename)
    {
        mSources ~= new Source(filename);
        return mSources.length - 1;
    }
    
    /**
     * Adds an additional path where imported modules will be searched.
     * Invalid paths will not cause an error.
     * The current working directory of the process is always checked,
     * and does not need to be added.
     */
    nothrow void addImportPath(string path)
    {
        mImportPaths ~= path;
    }
    
    /**
     * Returns a TokenStream for each source attached.
     * Throws: Exception if no sources have been added.
     *         CompilerError if one of the sources has an error.
     */
    TokenStream[] lex()
    {
        if (mSources.length == 0) {
            throw new Exception("no sources attached.");
        }
        mTokenStreams = new TokenStream[mSources.length];
        foreach (i, src; mSources) {
            mTokenStreams[i] = .lex(src);
        }
        return mTokenStreams;
    }
    
    /**
     * Parses each lexed Source and returns a Module for each.
     * Throws: Exception if nothing has been lexed.
     *         CompilerError if one of the parsings results in an error.
     */
    Module[] parse()
    {
        if (mTokenStreams.length == 0) {
            throw new Exception("tried to parse before lexing.");
        }
        
        {
            // Hack to check the custom parser.
            import d.parser.dmodule;
            foreach (i, ts; mTokenStreams) {
                .parseModule(ts);
            }
            
            lex();
        }
        
        mModules = new Module[mTokenStreams.length];
        foreach (i, ts; mTokenStreams) {
            mModules[i] = .parse(ts);
        }
        return mModules;
    }
    
    protected Module[] mModules;
    protected TokenStream[] mTokenStreams;
    protected Source[] mSources;
    protected string[] mImportPaths;
}
