/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */
module sdc.asttojson.base;

public import libdjson.json;

import sdc.ast.base;
import sdc.ast.sdcmodule;


JSONObject toJSON(Module parseTree)
{
    return prettyModuleDeclaration(parseTree.moduleDeclaration);
}

JSONObject prettyModuleDeclaration(ModuleDeclaration modDect)
{
    auto root = new JSONObject();
    root["ModuleDeclaration"] = prettyQualifiedName(modDect.name);
    return root;
}

JSONObject prettyQualifiedName(QualifiedName name)
{
    auto root = new JSONObject;
    auto qualifiedName = new JSONObject();
    auto names = new JSONArray();
    foreach (ident; name.identifiers) {
        names ~= prettyIdentifier(ident);
    }
    qualifiedName["Names"] = names;
    qualifiedName["LeadingDot"] = prettyBool(name.leadingDot);
    root["QualifiedName"] = qualifiedName;
    return root;
}

JSONObject prettyIdentifier(Identifier ident)
{
    auto root = new JSONObject();
    root["Identifier"] = new JSONString(ident.value);
    return root;
}

JSONString prettyBool(bool b)
{
    return new JSONString(b ? "yes" : "no");
}
