/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdctemplate;

import std.conv;
import std.stdio;
import std.string;
import std.exception;

import sdc.compilererror;
import sdc.extract.base;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.value;
import sdc.gen.type;
import ast = sdc.ast.all;


Value genTemplateInstance(ast.TemplateInstance instance, Module mod)
{
    auto name  = extractIdentifier(instance.identifier);
    auto store = mod.search(name);
    if (store is null || store.storeType != StoreType.Template) {
        throw new CompilerError(instance.identifier.location, format("'%s' is not a template.", name));
    }
    auto tdecl = store.getTemplate();

    
    string[] parameterNames;
    foreach (parameter; tdecl.parameterList.parameters) {
        if (parameter.type != ast.TemplateParameterType.Type) {
            throw new CompilerPanic(parameter.location, "only simple type template parameters are supported.");
        }
        auto asType = cast(ast.TemplateTypeParameter) parameter.node;
        parameterNames ~= extractIdentifier(asType.identifier);
    }
    

    if (tdecl.cacheTree is null) {
        tdecl.cacheTree = new TemplateCacheNode();
    }
    
    TemplateCacheNode node;
    mod.pushScope();
    scope (exit) mod.popScope();
    auto theScope = mod.currentScope;
  
    if (instance.argument !is null) {
        // Foo!argument
        if (parameterNames.length != 1) {
            throw new CompilerError(instance.location, format("template instantiated with 1 parameter, when it has %s required parameters.", parameterNames.length)); 
        }
        node = retrieveCacheNodeFromSingleArgument(tdecl.cacheTree, instance.argument, mod);
        
        final switch (instance.argument.type) with (ast.TemplateSingleArgumentType) if (node.cache is null) { 
        case BasicType:
            auto type = primitiveTypeToBackendType(enforce(cast(ast.PrimitiveType) instance.argument.node), mod);
            theScope.add(parameterNames[0], new Store(type));
            break;
        case Identifier:
        case CharacterLiteral:
        case StringLiteral:
        case IntegerLiteral:
        case FloatLiteral:
        case True:
        case False:
        case Null:
        case __File__:
        case __Line__:
            throw new CompilerPanic(instance.argument.location, "unsupported template argument type.");
        }
    } else {
        // Foo!(arguments)
        if (parameterNames.length != instance.arguments.length) {
            throw new CompilerError(instance.location, format("template instantiated with %s parameter, when it has %s required parameters.", instance.arguments.length, parameterNames.length)); 
        }
        node = retrieveCacheNode(tdecl.cacheTree, instance.arguments, mod);
        foreach (i, argument; instance.arguments) final switch (argument.type) with (ast.TemplateArgumentType) {
        case Type:
            auto type = astTypeToBackendType(cast(ast.Type) argument.node, mod, OnFailure.DieWithError);
            theScope.add(parameterNames[i], new Store(type));
            break;
        case AssignExpression:
        case Symbol:
            throw new CompilerPanic(argument.location, "unsupported template argument type.");
        }
    }
    if (node.cache !is null) {
        return node.cache;
    }
    
    foreach (declDef; tdecl.declDefs) {
        declDef.buildStage = ast.BuildStage.Unhandled;
        genDeclarationDefinition(declDef, mod);
    }
    
    node.cache = new ScopeValue(mod, instance.location, theScope);
    return node.cache;
}

TemplateCacheNode retrieveCacheNodeFromSingleArgument(TemplateCacheNode root, ast.TemplateSingleArgument argument, Module mod)
{
    final switch (argument.type) with (ast.TemplateSingleArgumentType) { 
    case BasicType:
        auto type = primitiveTypeToBackendType(enforce(cast(ast.PrimitiveType) argument.node), mod);
        foreach (child; root.children) {
            if (child.type == type.dtype) {
                return child;
            }
        }
        auto child = new TemplateCacheNode();
        child.type = type.dtype;
        root.children ~= child; 
        return child;       
    case Identifier:
    case CharacterLiteral:
    case StringLiteral:
    case IntegerLiteral:
    case FloatLiteral:
    case True:
    case False:
    case Null:
    case __File__:
    case __Line__:
        throw new CompilerPanic(argument.location, "unsupported template argument type.");
    }
    // Never reached.
}

TemplateCacheNode retrieveCacheNode(TemplateCacheNode root, ast.TemplateArgument[] arguments, Module mod)
{
    auto current = root;
    ARGUMENTLOOP: foreach (argument; arguments) final switch (argument.type) with (ast.TemplateArgumentType) {
    case Type:
        auto type = astTypeToBackendType(enforce(cast(ast.Type) argument.node), mod, OnFailure.DieWithError);
        foreach (child; current.children) {
            if (child.type == type.dtype) {
                current = child;
                continue ARGUMENTLOOP;
            }
        }
        auto child = new TemplateCacheNode();
        child.type = type.dtype;
        current.children ~= child;
        current = child;
        break;
    case AssignExpression:
    case Symbol:
        throw new CompilerPanic(argument.location, "unsupported template argument type.");
    }
    return current;
} 

void genTemplateDeclaration(ast.TemplateDeclaration decl, Module mod)
{
    mod.currentScope.add(extractIdentifier(decl.templateIdentifier), new Store(decl));
}


class TemplateCacheNode
{
    DType type = DType.None;
    TemplateCacheNode[] children;
    ScopeValue cache = null;
}
