/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.declaration;

import std.string;
import std.typecons;

import llvm.c.Core;

import sdc.util;
import sdc.compilererror;
import sdc.ast.expression;
import sdc.ast.declaration;
import sdc.ast.aggregate;
import sdc.gen.expression;
import sdc.gen.semantic;
import sdc.gen.type;
import sdc.gen.extract;
import sdc.gen.statement;


void declareDeclaration(Declaration decl, Semantic semantic)
{
    final switch (decl.type) {
    case DeclarationType.Variable:
        break;
    case DeclarationType.Function:
        declareFunctionDeclaration(cast(FunctionDeclaration) decl.node, semantic);
        break;
    }
}

void genDeclaration(Declaration decl, Semantic semantic)
{
    final switch (decl.type) {
    case DeclarationType.Variable:
        genVariableDeclaration(cast(VariableDeclaration) decl.node, semantic);
        break;
    case DeclarationType.Function:
        auto FD = cast(FunctionDeclaration) decl.node;
        if (FD.functionBody !is null) {
            genFunctionDeclaration(cast(FunctionDeclaration) decl.node, semantic);
        }
        break;
    }
}

void genVariableDeclaration(VariableDeclaration decl, Semantic semantic)
{
    // Go elsewhere for aggregates.
    if (decl.type.type == TypeType.UserDefined) {
        auto tname = extractQualifiedName((cast(UserDefinedType) decl.type.node).qualifiedName);
        auto dt = semantic.getDeclaration(tname);
        if (dt !is null && dt.stype == StoreType.Aggregate) {
            return genAggregateInstance(decl, semantic);
        }
    }
        
    auto type = typeToLLVM(decl.type, semantic);
    foreach (declarator; decl.declarators) {
        auto name = extractIdentifier(declarator.name);
        auto d = semantic.getDeclaration(name);
        if (d !is null) {
            error(decl.location, format("declaration '%s' shadows declaration at '%s'.", name, d.declaration.location));
        }
        auto store = new VariableStore();
        store.declaration = new SyntheticVariableDeclaration(decl, declarator);
        store.type = type;
        if (decl.isAlias) {
            if (declarator.initialiser !is null) {
                error(declarator.location, "alias declaration may not have an initialiser.");
            }
            semantic.setDeclaration(name, store);
            continue;
        }
        store.value = LLVMBuildAlloca(semantic.builder, type, toStringz(name));
        
        if (declarator.initialiser !is null) {
            genInitialiser(declarator.initialiser, semantic, store.value, store.type);
        } else {
            LLVMBuildStore(semantic.builder, LLVMConstInt(type, 0, false), store.value);
        }
        semantic.setDeclaration(name, store);
    }
}

void genAggregateInstance(VariableDeclaration decl, Semantic semantic)
{
    auto type = typeToLLVM(decl.type, semantic);
    foreach (declarator; decl.declarators) {
        auto name = extractIdentifier(declarator.name);
        auto d = semantic.getDeclaration(name);
        if (d !is null) {
            error(decl.location, format("aggregate '%s' shadows declaration at '%s'.", name, d.declaration.location));
        }
        
        auto store = new AggregateInstance();
        
        auto tname = extractQualifiedName((cast(UserDefinedType) decl.type.node).qualifiedName);
        auto dt = semantic.getDeclaration(tname);
        if (dt is null || dt.stype != StoreType.Aggregate) {
            error(decl.location, "ICE: attempted to aggregate declare an instance of a non-aggregate type.");
        }
        
        store.declaration = decl;
        store.type = dt.type;
        store.aggregateType = cast(AggregateStore) dt;
        store.value = LLVMBuildAlloca(semantic.builder, type, toStringz(name));
        // TODO: aliases
        if (declarator.initialiser !is null) {
            genInitialiser(declarator.initialiser, semantic, store.value, store.type);
        }
        
        semantic.setDeclaration(name, store);
    }
}

void declareFunctionDeclaration(FunctionDeclaration decl, Semantic semantic)
{
    LLVMTypeRef[] params;
    foreach (parameter; decl.parameters) {
        params ~= typeToLLVM(parameter.type, semantic);
    }
    auto FT = LLVMFunctionType(typeToLLVM(decl.retval, semantic), params.ptr, params.length, false);
    auto F  = LLVMAddFunction(semantic.mod, toStringz(extractIdentifier(decl.name)), FT);
    auto store = new FunctionStore();
    store.declaration = decl;
    store.type = FT;
    store.value = F;
    semantic.setDeclaration(extractIdentifier(decl.name), store);
}

void genFunctionDeclaration(FunctionDeclaration decl, Semantic semantic)
{
    auto d = semantic.getDeclaration(extractIdentifier(decl.name));
    if (d is null || d.stype != StoreType.Function) {
        error(decl.location, "ICE: attempted to define non-existent function.");
    }
    
    auto F  = d.value;
    auto FT = d.type;
    auto BB = LLVMAppendBasicBlockInContext(semantic.context, F, "entry");
    LLVMPositionBuilderAtEnd(semantic.builder, BB);
        
    semantic.functionType = FT;
    semantic.currentFunction = F;
    semantic.pushScope();
    
    auto numberOfParams = LLVMCountParams(F);
    assert(numberOfParams == decl.parameters.length);
    foreach (i, parameter; decl.parameters) {
        // Anonymous parameter.
        if (parameter.identifier is null) continue;
        
        auto name = extractIdentifier(parameter.identifier);
        auto p = LLVMGetParam(F, i);
        auto v = LLVMBuildAlloca(semantic.builder, LLVMTypeOf(p), toStringz(name));
        LLVMBuildStore(semantic.builder, p, v);
        auto synth = new SyntheticVariableDeclaration();
        synth.location = parameter.location;
        synth.identifier = parameter.identifier;
        synth.type = parameter.type;
        auto store = new VariableStore();
        store.declaration = synth;
        store.value = v;
        store.type = LLVMTypeOf(p);
        semantic.setDeclaration(extractIdentifier(parameter.identifier), store);
    }
        
    genFunctionBody(decl.functionBody, semantic);
    if (!semantic.currentScope.builtReturn) {
        if (LLVMGetReturnType(FT) == LLVMVoidTypeInContext(semantic.context)) {
            LLVMBuildRetVoid(semantic.builder);
        } else {
            error(decl.location, "control reaches end of non-void function.");
        }
    }
    
    semantic.popScope();
    semantic.functionType = null;
    semantic.currentFunction = null;
}

void genFunctionBody(FunctionBody fbody, Semantic semantic)
{
    genBlockStatement(fbody.statement, semantic);
}

void genInitialiser(Initialiser initialiser, Semantic semantic, LLVMValueRef var, LLVMTypeRef type)
{
    final switch (initialiser.type) {
    case InitialiserType.Void:
        LLVMBuildStore(semantic.builder, LLVMGetUndef(type), var);
        break;
    case InitialiserType.AssignExpression:
        auto expr = genAssignExpression(cast(AssignExpression) initialiser.node, semantic);
        auto init = LLVMBuildLoad(semantic.builder, expr, "init");
        if (LLVMTypeOf(init) != type) {
            genImplicitCast(initialiser.location, semantic, type, init);
        }
        LLVMBuildStore(semantic.builder, init, var);
        break;
    }
}

void declareAggregateDeclaration(AggregateDeclaration decl, Semantic semantic)
{
    if (decl.type == AggregateType.Union) {
        error(decl.location, "ICE: unions are unimplemented.");
    }
    
    auto store = new AggregateStore();
    store.declaration = decl;
    auto name = extractIdentifier(decl.name);
    auto d = semantic.getDeclaration(name);
    if (d !is null) {
        error(decl.location, format("already a definition of '%s' at %s.", name, d.declaration.location));
    }
    semantic.setDeclaration(name, store);
    if (decl.structBody is null) {
        return;
    }
    
    auto fields = declareStructBody(decl.structBody, semantic, store);
    store.type = LLVMStructTypeInContext(semantic.context, fields.ptr, fields.length, false);
}

LLVMTypeRef[] declareStructBody(StructBody structBody, Semantic semantic, AggregateStore store)
{
    LLVMTypeRef[] fields;
    foreach (decl; structBody.declarations) {
        semantic.pushScope();
        final switch (decl.type) {
        case StructBodyDeclarationType.Declaration:
            auto d = cast(Declaration) decl.node;
            genDeclaration(cast(Declaration) decl.node, semantic);
            switch (d.type) {
            case DeclarationType.Variable:
                auto v = cast(VariableDeclaration) d.node;
                foreach (declarator; v.declarators) {
                    auto name = extractIdentifier(declarator.name);
                    auto vstore = semantic.getDeclaration(name);
                    assert(vstore);
                    store.fields[name] = fields.length;
                    fields ~= vstore.type;
                }
                break;
            default:
                break;
            }
            break;
        case StructBodyDeclarationType.StaticConstructor:
        case StructBodyDeclarationType.StaticDestructor:
        case StructBodyDeclarationType.Invariant:
        case StructBodyDeclarationType.Unittest:
        case StructBodyDeclarationType.StructAllocator:
        case StructBodyDeclarationType.StructDeallocator:
        case StructBodyDeclarationType.StructConstructor:
        case StructBodyDeclarationType.StructPostblit:
        case StructBodyDeclarationType.StructDestructor:
        case StructBodyDeclarationType.AliasThis:
            error(decl.location, "ICE: unimplemented struct member.");
            break;
        }
        semantic.popScope();
    }
    return fields;
}
