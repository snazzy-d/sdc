/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.global;

import std.string;

import sdc.compilererror;
import sdc.util;
import sdc.source;
import sdc.tokenstream;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.value;
import sdc.gen.type;

enum ModuleState
{
    Unhandled,
    PendingResolution,
    ReadyToBuild,
    Complete,
}

enum TUSource
{
    Import,
    Compilation,
}

class TranslationUnit
{
    TUSource tusource;
    ModuleState state;
    string filename;
    Source source;
    TokenStream tstream;
    ast.Module aModule;
    Module gModule;
    bool compile = true;
}

shared bool isDebug = true;
shared bool unittestsEnabled = false;
shared bool coloursEnabled = true;
__gshared ast.DeclarationDefinition[] implicitDeclDefs;
shared int bits;

bool isReserved(string s)
{
    return s in reservedVersionIdentifiers || (s.length >= 2 && s[0 .. 2] == "D_");
}

void setVersion(string s)
{
    if (isReserved(s)) {
        throw new CompilerError(format("cannot specify reserved version identifier '%s'", s));
    }
    if (s in versionIdentifiers) {
        throw new CompilerError(format("version identifier '%s' already defined", s));
    }
    versionIdentifiers[s] = true;
}

private void specifyAndReserve(string s)
{
    setVersion(s);
    reservedVersionIdentifiers[s] = true;
}

void setDebug(string s)
{
    if (s in debugIdentifiers) {
        throw new CompilerError(format("debug identifier '%s' already defined", s));
    }
    debugIdentifiers[s] = true;
}

bool isVersionIdentifierSet(string s)
{
    return (s in versionIdentifiers) !is null;
}

bool isDebugIdentifierSet(string s)
{
    return (s in debugIdentifiers) !is null;
}

void addTranslationUnit(string key, TranslationUnit val)
{
    translationUnits[key] = val;
}

TranslationUnit getTranslationUnit(string key)
{
    return translationUnits.get(key, null);
}

TranslationUnit[] getTranslationUnits()
{
    return translationUnits.values;
}

Module dummyModule(Module parent)
{
    if (mDummyModule is null) {
        mDummyModule = parent.dup;
    }
    return mDummyModule;
}

void globalInit(string arch)
{
    switch (arch) {
    case "x86":
        specifyAndReserve("LittleEndian");
        specifyAndReserve("X86");
        reservedVersionIdentifiers["X86_64"] = true;
        bits = 32;
        break;
    case "x86-64":
        specifyAndReserve("LittleEndian");
        specifyAndReserve("X86_64");
        reservedVersionIdentifiers["X86"] = true;
        bits = 64;
        break;
    case "ppc32": 
        specifyAndReserve("BigEndian");
        bits = 32;
        break;
    case "ppc64":
        specifyAndReserve("BigEndian");
        bits = 64;
        break;
    case "arm":
        specifyAndReserve("LittleEndian");  // TODO: bi-endian archs
        bits = 32;
    default:
        throw new CompilerError("Unknown arch string '" ~ arch ~ "'");
    }
    
    if (bits != 32 && bits != 64) {
        throw new CompilerError("Specified architecture must be of 32 or 64 bits");
    }
    
    reservedVersionIdentifiers["none"] = true;  // Guaranteed never to be defined.
    // Predefined version identifiers may not be set, even if they aren't active.
    reservedVersionIdentifiers["DigitalMars"] = true;
    version (Windows) {
        specifyAndReserve("Windows");
        if (bits == 32) {
            specifyAndReserve("Win32");
            reservedVersionIdentifiers["Win64"] = true;
        } else {
            specifyAndReserve("Win64");
            reservedVersionIdentifiers["Win32"] = true;
        }
    } else {
        reservedVersionIdentifiers["Windows"] = true;
        reservedVersionIdentifiers["Win32"] = true;
        reservedVersionIdentifiers["Win64"] = true;
    }
    version (linux) {
        specifyAndReserve("linux");
    } else {
        reservedVersionIdentifiers["linux"] = true;
    }
    version (Posix) {
        specifyAndReserve("Posix");
    } else {
        reservedVersionIdentifiers["Posix"] = true;
    }
    if (isVersionIdentifierSet("LittleEndian")) {
        reservedVersionIdentifiers["BigEndian"] = true;
    } else {
        reservedVersionIdentifiers["LittleEndian"] = true;
    }
    
    
    specifyAndReserve("all");                   // Guaranteed to be defined by all implementations.
    specifyAndReserve("SDC");                   // Vendor specification.
    versionIdentifiers["D_Version2"] = true;    // D version supported is 2.
    
    if (bits == 64) {
        versionIdentifiers["D_LP64"] = true;
        // Note that all "D_" identifiers are reserved, so no need to manually do so.
    }
}

Type getSizeT(Module mod)
{
    if (bits == 32) {
        return new UintType(mod);
    } else if (bits == 64) {
        return new UlongType(mod);
    } else {
        assert(false);
    }
}

private shared bool[string] reservedVersionIdentifiers;
private shared bool[string] versionIdentifiers;
private shared bool[string] debugIdentifiers;
private __gshared TranslationUnit[string] translationUnits;
private Module mDummyModule;


// Runtime functions that the compiler needs to be able to call.
FunctionValue gcAlloc;
FunctionValue gcRealloc;
