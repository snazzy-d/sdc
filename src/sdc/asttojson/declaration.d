/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.asttojson.declaration;

import sdc.util;
import sdc.token;
import sdc.ast.declaration;
import sdc.asttojson.base;


JSONObject prettyDeclaration(Declaration declaration)
{
    auto root = new JSONObject();
    root["isAlias"] = prettyBool(declaration.isAlias);
    
    auto storage = new JSONArray();
    foreach (storageClass; declaration.storageClasses) {
        storage ~= prettyStorageClass(storageClass);
    }
    root["StorageClasses"] = storage;
    
    if (declaration.basicType !is null) {
        root["BasicType"] = prettyBasicType(declaration.basicType);
    }
    
    return root;
}

JSONString prettyStorageClass(StorageClass storageClass)
{
    return new JSONString(tokenToString[cast(TokenType)storageClass.type]);
}

JSONObject prettyBasicType(BasicType basicType)
{
    auto root = new JSONObject();
    auto asToken = cast(TokenType) basicType.type;
    
    if (contains(ONE_WORD_TYPES, asToken) || contains(PAREN_TYPES, asToken)) {
        root["Type"] = new JSONString(tokenToString[asToken]);
    }
    
    if (basicType.secondType !is null) {
        root["SecondType"] = new JSONString("temp!!!");
    }
    
    if (basicType.qualifiedName !is null) {
        root["QualifiedName"] = prettyQualifiedName(basicType.qualifiedName);
    }
    
    return root;
}
