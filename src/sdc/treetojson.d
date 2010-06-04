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
    return prettyModuleDeclaration(parseTree.moduleDeclaration);
}

private:

JSONObject prettyModuleDeclaration(ModuleDeclaration modDect)
{
    auto root = new JSONObject();
    root["ModuleDeclaration"] = prettyQualifiedName(modDect.name);
    return root;
}

JSONObject prettyQualifiedName(QualifiedName name)
{
    auto root = new JSONObject;
    auto qualifiedName = new JSONArray();
    foreach (ident; name.identifiers) {
        qualifiedName ~= prettyIdentifier(ident);
    }
    root["QualifiedName"] = qualifiedName;
    return root;
}

JSONObject prettyIdentifier(Identifier ident)
{
    auto root = new JSONObject();
    root["Identifier"] = new JSONString(ident.token.value);
    return root;
}
