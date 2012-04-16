/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.binder.c;
version (xlang):

import std.container;
import std.conv;
import std.stdio;
import std.string;

import clang.c.Index;

import sdc.location;
import sdc.ast.attribute;
import sdc.gen.sdcfunction;
import sdc.gen.sdcmodule;
import sdc.gen.type;


void bindC(Module mod, string filename)
{
    auto index = clang_createIndex(true, true);
    scope (exit) clang_disposeIndex(index);
    auto tunit = clang_createTranslationUnitFromSourceFile(index, toStringz(filename), 0, null, 0, null);
    scope (exit) clang_disposeTranslationUnit(tunit);
    auto cursor = clang_getTranslationUnitCursor(tunit);
    
    clang_visitChildren(cursor, &visitor, cast(void*) mod);
}

string toString(CXString str)
{
    auto s = to!string(clang_getCString(str));
    clang_disposeString(str);
    return s;
}

Type mapType(CXType type, Module mod)
{
    switch (type.kind) with (CXTypeKind) {
    case CXType_Int:
        return new IntType(mod);
    default:
        assert(false);
    }
}

extern (C) CXChildVisitResult visitor(CXCursor cursor, CXCursor parent, CXClientData data)
{
    auto mod = cast(Module) data;
    assert(mod !is null);
    
    auto kind = clang_getCursorKind(cursor);
    switch (kind) with (CXCursorKind) {
    case CXCursor_FunctionDecl: bindFunction(mod, cursor); break; 
    default:
        break;
    }
    
    return CXChildVisitResult.CXChildVisit_Recurse;
}

/**
 * Add a prototype for a given C function to Module mod.
 */
void bindFunction(Module mod, CXCursor func)
{
    auto type = clang_getCursorType(func);
    assert(type.kind == CXTypeKind.CXType_FunctionProto);
    auto tmps = clang_getCursorSpelling(func);
        
    auto name = toString(tmps);
    auto rtype = clang_getResultType(type);
    Array!CXCursor params;
    clang_visitChildren(func, &gatherCursors, &params);
    
    auto retval = mapType(rtype, mod);
    Type[] args;     
    foreach (param; params) {
        auto ptype = clang_getCursorType(param);
        args ~= mapType(ptype, mod);
    }
    
    auto fntype = new FunctionType(mod, retval, args, false);
    fntype.linkage = Linkage.ExternC;
    fntype.declare();
    auto fn = new Function(fntype);
    fn.simpleName = name;
    fn.add(mod);
    Location location;
    mod.currentScope.add(name, new Store(fn, location));
}

/**
 * Call back for gathering all cursors that are a the direct children of a parent.
 */
extern (C) CXChildVisitResult gatherCursors(CXCursor cursor, CXCursor parent, CXClientData data)
{
    auto cursors = cast(Array!(CXCursor)*) data;
    assert(cursors !is null);
    cursors.insertBack(cursor);
    return CXChildVisitResult.CXChildVisit_Continue;
}
