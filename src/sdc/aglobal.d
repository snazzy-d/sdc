/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 *
 * Fun fact: this module is named 'aglobal.d' 
 * to ensure it is compiled first and work around a DMD template bug. 
 */
module sdc.aglobal;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.json;
import std.path;
import std.string;
import std.stdio;

import sdc.compilererror;
import sdc.util;
import sdc.source;
import sdc.tokenstream;
import sdc.location;
import sdc.terminal;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.value;
import sdc.gen.type;
import sdc.gen.sdcfunction;

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

bool isDebug = true;
bool unittestsEnabled = false;
bool coloursEnabled = true;
bool verboseCompile = false;
bool PIC = false;
int bits;
string[] importPaths;
string confLocation;  // For verbose compiles

enum VerbosePrintColour
{
    Normal,
    Red = ConsoleColour.Red,
    Green = ConsoleColour.Green,
    Blue = ConsoleColour.Blue,
    Yellow = ConsoleColour.Yellow
}

int verboseIndent;
void verbosePrint(lazy string s, VerbosePrintColour colour = VerbosePrintColour.Normal)
{
    if (!verboseCompile) return;

    assert(verboseIndent >= 0);
    foreach (i; 0 .. verboseIndent) write(" ");

    if (colour == VerbosePrintColour.Normal) {
        writeln(s);
    } else {
        writeColouredText(stdout, cast(ConsoleColour) colour, {writeln(s);});
    }
}

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
    assert(val !is null);
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
        break;
    default:
        throw new CompilerError("Unknown arch string '" ~ arch ~ "'.");
    }
    
    if (bits != 32 && bits != 64) {
        throw new CompilerError("Specified architecture must be of 32 or 64 bits.");
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

version(Windows) extern(Windows) private
{
    void* GetModuleHandleA(const char* modName);
    uint GetModuleFileNameA(void* mod, char* path, uint pathLen);
    import std.c.string : strlen;
    import std.path : dirname;
}

void loadConfig(ref string[] args)
{
    void checkType(JSONValue val, JSON_TYPE type, string msg)
    {
        if (val.type != type) {
            throw new CompilerError("malformed config: " ~ msg);
        }
    }
    
    string[] getStringArray(JSONValue object, string member)
    {
        string[] results;
        if (auto p = member in object.object) {
            auto array = *p;
            checkType(array, JSON_TYPE.ARRAY, "non array typed " ~ member ~ ".");
            
            foreach (e; array.array) {
                checkType(e, JSON_TYPE.STRING, "non string array member.");
                results ~= e.str;
            }
        }
        return results;
    }
    
    version (Posix) string[] confLocations = ["~/.sdc.conf", "/etc/sdc.conf"];
    else version(Windows)
    {
        char[256] filePath;
        GetModuleFileNameA(GetModuleHandleA(null), filePath.ptr, filePath.length);
        string exeDirPath = cast(immutable)dirname(filePath.ptr[0..strlen(filePath.ptr)]);
        string[] confLocations = [exeDirPath ~ "\\sdc.conf"];
    }
    else pragma(error, "please implement global.loadConfig for your platform.");
    
    bool existsWrapper(string s) { return exists(s); }  // WORKAROUND 2.053
    auto confs = array( filter!existsWrapper(map!expandTilde(confLocations)) );
    if (confs.length == 0) {
        // Try to soldier on without a config file.
        return;
    }
    auto conf = cast(string) read(confs[0]);
    confLocation = confs[0];
    
    auto confRoot = parseJSON(conf);
    checkType(confRoot, JSON_TYPE.OBJECT, "no root object."); 
    
    importPaths ~= array( map!expandTilde(getStringArray(confRoot, "defaultImportPaths")) );
    if (args.length > 1) {
        args = args[0] ~ getStringArray(confRoot, "defaultFlags") ~ args[1 .. $];
    } else {
        args = args[0] ~ getStringArray(confRoot, "defaultFlags");
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

Type getPtrdiffT(Module mod)
{
    if (bits == 32) {
        return new IntType(mod);
    } else if (bits == 64) {
        return new LongType(mod);
    } else {
        assert(false);
    }
}

// Urgh
Value newSizeT(Module mod, Location loc, ulong init)
{
    if (bits == 32) {
        return new UintValue(mod, loc, cast(uint)init);
    } else if (bits == 64) {
        return new UlongValue(mod, loc, init);
    } else {
        assert(false);
    }
}

Value newPtrdiffT(Module mod, Location loc, long init)
{
    if (bits == 32) {
        return new IntValue(mod, loc, cast(int)init);
    } else if (bits == 64) {
        return new LongValue(mod, loc, init);
    } else {
        assert(false);
    }
}

private shared bool[string] reservedVersionIdentifiers;
private shared bool[string] versionIdentifiers;
private shared bool[string] debugIdentifiers;
private __gshared TranslationUnit[string] translationUnits;
