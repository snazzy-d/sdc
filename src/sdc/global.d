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
__gshared ast.DeclarationDefinition[] implicitDeclDefs;

bool isReserved(string s)
{
    return s in reservedVersionIdentifiers || (s.length >= 2 && s[0 .. 2] == "D_");
}

void setVersion(string s)
{
    if (isReserved(s)) {
        throw new CompilerError(format("cannot specify reserved version identifier '%s'.", s));
    }
    if (s in versionIdentifiers) {
        throw new CompilerError(format("version identifier '%s' already defined.", s));
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
        throw new CompilerError(format("debug identifier '%s' already defined.", s));
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

static this()
{
    reservedVersionIdentifiers["none"] = true;  // Guaranteed never to be defined.
    specifyAndReserve("all");                   // Guaranteed to be defined by all implementations.
    specifyAndReserve("SDC");                   // Vendor specification.
    versionIdentifiers["D_Version2"] = true;    // D version supported is 2.
}

private shared bool[string] reservedVersionIdentifiers;
private shared bool[string] versionIdentifiers;
private shared bool[string] debugIdentifiers;
private __gshared TranslationUnit[string] translationUnits;
private Module mDummyModule;


// Runtime functions that the compiler needs to be able to call.
__gshared FunctionValue gcAlloc;
