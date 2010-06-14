/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */
module sdc.asttojson.declaration;

import sdc.token;
import sdc.ast.declaration;
import sdc.asttojson.base;

JSONObject prettyDeclaration(Declaration declaration)
{
    auto root = new JSONObject();
    root["alias"] = new JSONString(declaration.isAlias ? "true" : "false");
    
    auto storage = new JSONArray();
    foreach (storageClass; declaration.storageClasses) {
        storage ~= prettyStorageClass(storageClass);
    }
    root["StorageClasses"] = storage;
    
    return root;
}

JSONString prettyStorageClass(StorageClass storageClass)
{
    return new JSONString(tokenToString[cast(TokenType)storageClass.type]);
}
