/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 * 
 * treetojson.d: translate a parse tree into a JSON object.
 */ 
module sdc.treetojson;

import libdjson.json;

import sdc.ast.base;
import sdc.ast.sdcmodule;


JSONObject toJSON(Module parseTree)
{
    auto root = new JSONObject();
    prettyModuleDeclaration(parseTree.moduleDeclaration, root);
    return root;
}

private:

void prettyModuleDeclaration(ModuleDeclaration modDec, JSONObject root)
{
    auto localRoot = new JSONObject();
    prettyQualifiedName(modDec.name, localRoot);
    root["ModuleDeclaration"] = localRoot;
}

void prettyQualifiedName(QualifiedName name, JSONObject root)
{
    auto localRoot = new JSONArray();
    foreach (ident; name.identifiers) {
        auto r = new JSONObject();
        prettyIdentifier(ident, r);
        localRoot ~= r;
    }
    root["QualifiedName"] = localRoot;
}

void prettyIdentifier(Identifier ident, JSONObject root)
{
    root["Identifier"] = new JSONString(ident.token.value);
}
