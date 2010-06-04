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
        localRoot ~= prettyIdentifier(ident);
    }
    root["QualifiedName"] = localRoot;
}

JSONString prettyIdentifier(Identifier ident)
{
    return new JSONString(ident.token.value);
}
