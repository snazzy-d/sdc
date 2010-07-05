/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.conv;
import std.stdio;
import std.string;

import sdc.util;
import sdc.primitive;
import sdc.compilererror;
import sdc.ast.all;
import sdc.ast.declaration;
import sdc.extract.base;
import sdc.extract.expression;
import sdc.gen.expression;
import sdc.gen.semantic;
import sdc.gen.attribute;
import sdc.gen.statement;
public import asmgen = sdc.gen.llvm.base;


void genModule(Module mod, File file)
{
    auto semantic = new Semantic();
    asmgen.emitComment(file, extractQualifiedName(mod.moduleDeclaration.name));
    
    // Find all top level declarations in the module; don't generate code.
    foreach (declarationDefinition; mod.declarationDefinitions) {
        declareDeclarationDefinition(declarationDefinition, file, semantic);
    }
    
    // Actually generate the code for the declarations.
    foreach (declarationDefinition; mod.declarationDefinitions) {
        genDeclarationDefinition(declarationDefinition, file, semantic);
    }
}


void declareDeclarationDefinition(DeclarationDefinition declDef, File file, Semantic semantic)
{
    switch (declDef.type) {
    case DeclarationDefinitionType.Declaration:
        return declareDeclaration(cast(Declaration) declDef.node, file, semantic);
    default:
        break;
    }
}

void genDeclarationDefinition(DeclarationDefinition declDef, File file, Semantic semantic)
{
    switch (declDef.type) {
    case DeclarationDefinitionType.Declaration:
        return genDeclaration(cast(Declaration) declDef.node, file, semantic);
    case DeclarationDefinitionType.AttributeSpecifier:
        return genAttributeSpecifier(cast(AttributeSpecifier) declDef.node, file, semantic);
    default:
        error(declDef.location, "unhandled DeclarationDefinition");
        assert(false);
    }
    assert(false);
}

void genAttributeSpecifier(AttributeSpecifier attributeSpecifier, File file, Semantic semantic)
{
    genAttribute(attributeSpecifier.attribute, file, semantic);
    if (attributeSpecifier.declarationBlock !is null) {
        genDeclarationBlock(attributeSpecifier.declarationBlock, file, semantic);
        semantic.popAttribute();
    }  // Otherwise, the attribute applies until the module's end.
}

void genDeclarationBlock(DeclarationBlock declarationBlock, File file, Semantic semantic)
{
    foreach (declarationDefinition; declarationBlock.declarationDefinitions) {
        genDeclarationDefinition(declarationDefinition, file, semantic);
    }
}

void declareDeclaration(Declaration declaration, File file, Semantic semantic)
{
    if (declaration.type == DeclarationType.Function) {
        declareFunctionDeclaration(cast(FunctionDeclaration) declaration.node, file, semantic);
    }
}

void genDeclaration(Declaration declaration, File file, Semantic semantic)
{
    if (declaration.type == DeclarationType.Function) {
        genFunctionDeclaration(cast(FunctionDeclaration) declaration.node, file, semantic);
    } else if (declaration.type == DeclarationType.Variable) {
        genVariableDeclaration(cast(VariableDeclaration) declaration.node, file, semantic);
    }
}

void declareVariableDeclaration(VariableDeclaration declaration, File file, Semantic semantic)
{
    bool global = semantic.currentScope is semantic.globalScope;
    
    auto primitive = fullTypeToPrimitive(declaration.type);
    foreach (declarator; declaration.declarators) {
        auto name = extractIdentifier(declarator.name);
        auto syn  = new SyntheticVariableDeclaration();
        syn.location = declaration.location;
        syn.type = declaration.type;
        syn.identifier = declarator.name;
        syn.initialiser = declarator.initialiser;
        try {
            semantic.addDeclaration(name, syn, global);
        } catch (RedeclarationError) {
            error(declarator.location, format("'%s' is already defined", name));
        }
    }
}

void genVariableDeclaration(VariableDeclaration declaration, File file, Semantic semantic)
{
    bool global = semantic.currentScope is semantic.globalScope;
    
    auto primitive = fullTypeToPrimitive(declaration.type);
    foreach (declarator; declaration.declarators) {
        auto name = extractIdentifier(declarator.name);
        auto syn = new SyntheticVariableDeclaration();
        syn.location = declaration.location;
        syn.type = declaration.type;
        syn.identifier = declarator.name;
        syn.initialiser = declarator.initialiser;
        try {
            semantic.addDeclaration(name, syn, global);
        } catch (RedeclarationError) {
            error(declarator.location, format("'%s' is already defined", name));
        }
        auto var = new Variable(name, primitive);
        if (!global) {
            asmgen.emitAlloca(file, var);
        } else {
            Value val = genConstantInitialiser(syn.initialiser, file, semantic);
            asmgen.emitGlobal(file, var, val);
        }
        
        if (!global && syn.initialiser !is null) {
            genInitialiser(syn.initialiser, file, semantic, var);
        } else if (!global) {
            genDefaultInitialiser(file, semantic, var);
        }
        syn.variable = var;
    }
}

void genInitialiser(Initialiser initialiser, File file, Semantic semantic, Variable var)
{
    if (initialiser.type == InitialiserType.Void) {
        return;
    }
    
    auto expr = genAssignExpression(cast(AssignExpression) initialiser.node, file, semantic);
    auto init = genVariable(removePointer(expr.primitive), "initialiser");
    asmgen.emitLoad(file, init, expr);
    asmgen.emitStore(file, var, init);
}

Value genConstantInitialiser(Initialiser initialiser, File file, Semantic semantic)
{
    if (initialiser is null || initialiser.type == InitialiserType.Void) {
        return new Constant("0", Primitive(32, 0));
    }
    
    auto expr = genAssignExpression(cast(AssignExpression) initialiser.node, file, semantic);
    if (expr.type != ValueType.Constant) {
        error(initialiser.location, "non-constant expression");
    }
    return cast(Constant) expr;
}

void genDefaultInitialiser(File file, Semantic semantic, Variable var)
{
    return asmgen.emitStore(file, var, new Constant("0", removePointer(var.primitive)));
}

void declareFunctionDeclaration(FunctionDeclaration declaration, File file, Semantic semantic)
{
    string functionName = extractIdentifier(declaration.name);
    try {
        semantic.addDeclaration(functionName, declaration);
    } catch (RedeclarationError) {
        error(declaration.location, format("function '%s' is already defined", functionName));
    }
}

void genFunctionDeclaration(FunctionDeclaration declaration, File file, Semantic semantic)
{
    bool global = semantic.currentScope is semantic.globalScope;
    asmgen.emitFunctionName(file, declaration);
    
    string functionName = extractIdentifier(declaration.name);
    assert(semantic.findDeclaration(functionName, global));
    semantic.pushScope();
    foreach (i, parameter; declaration.parameters) if (parameter.identifier !is null) {
        auto var = new SyntheticVariableDeclaration();
        var.location = parameter.location;
        var.type = parameter.type;
        var.identifier = parameter.identifier;
        var.isParameter = true;
        semantic.addDeclaration(extractIdentifier(var.identifier), var);
        asmgen.emitFunctionParameter(file, fullTypeToPrimitive(var.type), extractIdentifier(var.identifier), i == declaration.parameters.length - 1);
    }
    asmgen.emitFunctionBeginEnd(file);
    asmgen.incrementIndent();
    genBlockStatement(declaration.functionBody.statement, file, semantic);
    if (!semantic.currentScope.hasReturnStatement) {
        asmgen.emitVoidReturn(file);
    }
    
    semantic.popScope();
    asmgen.decrementIndent();
    asmgen.emitCloseFunctionDeclaration(file, declaration);
}
