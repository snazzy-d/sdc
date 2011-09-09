/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.util;

import core.runtime;
import std.conv;
import std.file;
import std.random;
import std.stdio;
import std.string;
import std.process;
import sdc.gen.sdcmodule; 

bool contains(T)(const(T)[] l, const T a)
{
    foreach (e; l) {
        if (e == a) {
            return true;
        }
    }
    return false;
}

void debugPrint(T...)(lazy string msg, T vs) 
{
    debug {
        write("DEBUG: ");
        writefln(msg, vs);
    }
}

void debugPrint(T)(T arg)
{
    debugPrint("%s", to!string(arg));
}

void debugPrintMany(T...)(T args)
{
    foreach (arg; args) {
        debugPrint("%s", to!string(arg));
    }
}

void dbga() { debugPrint("A"); }
void dbgb() { debugPrint("B"); }

enum Status : bool
{
    Failure,
    Success,
}

unittest
{
    auto fail = Status.Failure;
    auto success = Status.Success;
    assert(!fail);
    assert(success);
}

template MultiMixin(alias A, T...)
{
    static if (T.length) {
        mixin A!(T[0]);
        mixin MultiMixin!(A, T[1 .. $]);
    }
}

mixin template ImportToModule(T, string ARGS)
{
    override T importToModule(Module mod)
    {
        static typeof(this) cache = null;
        if (cache !is null) {
            return cache;
        }
        mixin("auto imprtd = new typeof(this)(" ~ ARGS ~ ");");
        cache = imprtd;
        foreach (member; __traits(allMembers, typeof(this))) { 
            enum m = "imprtd." ~ member; 
            static if (__traits(compiles, mixin(m ~ ".keys && " ~ m ~ ".values"))) {
                foreach (k, v; mixin(member)) {
                    static if (__traits(compiles, mixin(member ~ "[k].importToModule(mod)"))) {
                        mixin(m ~ "[k] = " ~ member ~ "[k].importToModule(mod);");
                    } else {
                        mixin(m ~ "[k] = " ~ member ~ "[k];");
                    }
                }
            } else static if (__traits(compiles, mixin(member ~ ".length && " ~ member ~ ".ptr")) && __traits(isScalar, mixin(member))) {
                static if (__traits(compiles, mixin(member ~ "[0].importToModule(mod)"))) {
                    mixin(m ~ " = new typeof(" ~ member ~ ")[" ~ member ~ ".length];");
                    foreach (i, e; mixin(member)) {
                        mixin(m ~ "[i] = " ~ member ~ "[i].importToModule(mod);");
                    }  
                } else {
                    mixin(m ~ " = " ~ member ~ ".dup;");
                } 
            } else static if (__traits(compiles, mixin(m ~ " = " ~ member ~ ".importToModule(mod)"))) {
                mixin("if (" ~ m ~ "!is null) " ~ m ~ " = " ~ member ~ ".importToModule(mod);");
            } else static if (__traits(compiles, mixin(m ~ " = " ~ member))) {
                mixin(m ~ " = " ~ member ~ ";");
            } 
        }
        static if (__traits(compiles, imprtd.declare())) {
            imprtd.declare();
        }
        static if (__traits(compiles, imprtd.add(mod, this.mangledName))) {
            imprtd.mod = null;
            imprtd.add(mod, this.mangledName);
        }
        return imprtd;
    }
}

T[] importList(T)(T[] list, Module mod)
{
    auto output = new T[list.length];
    foreach (i, e; list) {
        output[i] = e.importToModule(mod);
    }
    return output;
}

class ImportDummy(T)
{
    T importToModule(Module mod)
    {
        return T.init;
    }
}

Throwable.TraceInfo nullTraceHandler(void*)
{
    return null;
}

void disableStackTraces()
{
    Runtime.traceHandler = &nullTraceHandler;
}

void enableStackTraces()
{
    Runtime.traceHandler = &defaultTraceHandler;
}

/**
 * Generate a filename in a temporary directory that doesn't exist.
 *
 * Params:
 *   extension = a string to be appended to the filename. Defaults to an empty string.
 *
 * Returns: an absolute path to a unique (as far as we can tell) filename. 
 */
string temporaryFilename(string extension = "")
{
    version (Windows) {
        string prefix = getenv("TEMP") ~ '/';
    } else {
        string prefix = "/tmp/";
    }
    string filename;
    do {
        filename = randomString(32);
        filename = prefix ~ filename ~ extension;
    } while (exists(filename));
    return filename;
}

/// Generate a random string `length` characters long.
string randomString(size_t length)
{
    auto str = new char[length];
    foreach (i; 0 .. length) {
        char c;
        switch (uniform(0, 3)) {
        case 0:
            c = cast(char) uniform('0', '9' + 1);
            break;
        case 1:
            c = cast(char) uniform('a', 'z' + 1);
            break;
        case 2:
            c = cast(char) uniform('A', 'Z' + 1);
            break;
        default:
            assert(false);
        }
        str[i] = c;
    }
    return str.idup;    
}
