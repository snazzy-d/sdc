/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.asttojson.declaration;

import sdc.util;
import sdc.token;
import sdc.ast.declaration;
import sdc.ast.expression;
import sdc.asttojson.base;
import sdc.asttojson.expression;


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
    
    if (declaration.declarators !is null) {
        root["Declarators"] = prettyDeclarators(declaration.declarators);
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

JSONObject prettyDeclarators(Declarators declarators)
{
    auto root = new JSONObject();
    root["DeclaratorInitialiser"] = prettyDeclaratorInitialiser(declarators.declaratorInitialiser);
    return root;
}

JSONObject prettyDeclaratorInitialiser(DeclaratorInitialiser declaratorInitialiser)
{
    auto root = new JSONObject();
    root["Declarator"] = prettyDeclarator(declaratorInitialiser.declarator);
    return root;
}

JSONObject prettyDeclarator(Declarator declarator)
{
    auto root = new JSONObject();
    auto list = new JSONArray();
    foreach (basicType2; declarator.basicType2s) {
        list ~= prettyBasicType2(basicType2);
    }
    root["BasicType2s"] = list;
    return root;
}

JSONObject prettyBasicType2(BasicType2 basicType2)
{
    auto root = new JSONObject();
    root["Type"] = prettyBasicType2Type(basicType2.type);
    if (basicType2.firstAssignExpression !is null) {
        root["FirstAssignExpression"] = prettyAssignExpression(basicType2.firstAssignExpression);
    }
    if (basicType2.secondAssignExpression !is null) {
        root["SecondAssignExpression"] = prettyAssignExpression(basicType2.secondAssignExpression);
    }
    if (basicType2.aaType !is null) {
        root["AAType"] = prettyType(basicType2.aaType);
    }
    if (basicType2.parameters !is null) {
        root["Parameters"] = prettyParameters(basicType2.parameters);
    }
    return root;
}

JSONString prettyBasicType2Type(BasicType2Type type)
{
    switch (type) {
    case BasicType2Type.Pointer:
        return new JSONString("Pointer");
    case BasicType2Type.DynamicArray:
        return new JSONString("Dynamic Array");
    case BasicType2Type.StaticArray:
        return new JSONString("Static Array");
    case BasicType2Type.TupleSlice:
        return new JSONString("Tuple Slice");
    case BasicType2Type.AssociativeArray:
        return new JSONString("Associative Array");
    case BasicType2Type.Delegate:
        return new JSONString("Delegate");
    case BasicType2Type.Function:
        return new JSONString("Function");
    default:
        assert(false);
    }
    assert(false);
}

JSONObject prettyType(Type type)
{
    auto root = new JSONObject();
    return root;
}

JSONObject prettyParameters(Parameters parameters)
{
    auto root = new JSONObject();
    auto list = new JSONArray();
    foreach (p; parameters.parameters) {
        list ~= prettyParameter(p);
    }
    root["Parameters"] = list;
    return root;
}

JSONObject prettyParameter(Parameter parameter)
{
    auto root = new JSONObject();
    root["InOutType"] = new JSONString(parameter.inOutType == InOutType.None ? "None" : tokenToString[parameter.inOutType]);
    root["BasicType"] = prettyBasicType(parameter.basicType);
    auto list = new JSONArray();
    foreach (basicType2; parameter.basicType2s) {
        list ~= prettyBasicType2(basicType2);
    }
    root["BasicType2s"] = list;
    return root;
}
