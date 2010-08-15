/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import sdc.compilererror;
import sdc.global;
import ast = sdc.ast.all;
import sdc.extract.base;
import sdc.gen.sdcmodule;
import sdc.gen.declaration;
import sdc.gen.expression;


Module genModule(ast.Module astModule)
{
    auto mod = new Module(astModule.tstream.filename);
    try {
        realGenModule(astModule, mod);
    } catch (CompilerError e) {
        mod.dispose();
        throw e;
    }
    return mod;
}

void realGenModule(ast.Module astModule, Module mod)
{
    // Declare all data structures.
    foreach (declDef; astModule.declarationDefinitions) if (declDef.type == ast.DeclarationDefinitionType.Declaration) {
        auto decl = cast(ast.Declaration) declDef.node;
        if (decl.type == ast.DeclarationType.Variable) {
            declareVariableDeclaration(cast(ast.VariableDeclaration) decl.node, mod);
        }
    }
    
    // Declare functions.
    foreach (declDef; astModule.declarationDefinitions) {
        declareDeclarationDefinition(declDef, mod);
    }
    
    // Generate the code for the functions.
    foreach (declDef; astModule.declarationDefinitions) {
        genDeclarationDefinition(declDef, mod);
    }
}

void declareDeclarationDefinition(ast.DeclarationDefinition declDef, Module mod)
{
    switch (declDef.type) {
    case ast.DeclarationDefinitionType.Declaration:
        declareDeclaration(cast(ast.Declaration) declDef.node, mod);
        break;
    case ast.DeclarationDefinitionType.ConditionalDeclaration:
        declareConditionalDeclaration(cast(ast.ConditionalDeclaration) declDef.node, mod);
        break;
    default: break;
    }
}

void genDeclarationDefinition(ast.DeclarationDefinition declDef, Module mod)
{
    if (mod.currentScope.topLevelBail) return;
    switch (declDef.type) {
    case ast.DeclarationDefinitionType.Declaration:
        genDeclaration(cast(ast.Declaration) declDef.node, mod);
        break;
    case ast.DeclarationDefinitionType.ConditionalDeclaration:
        genConditionalDeclaration(cast(ast.ConditionalDeclaration) declDef.node, mod);
        break;
    default:
        error(declDef.location, "ICE: unhandled DeclarationDefinition.");
    }
}

void declareConditionalDeclaration(ast.ConditionalDeclaration decl, Module mod)
{
    switch (decl.type) {
    case ast.ConditionalDeclarationType.VersionSpecification:
        auto spec = cast(ast.VersionSpecification) decl.specification;
        if (spec.type == ast.SpecificationType.Identifier) {
            auto ident = extractIdentifier(cast(ast.Identifier) spec.node);
            setVersion(ident);
        } else {
            auto n = extractIntegerLiteral(cast(ast.IntegerLiteral) spec.node);
            versionLevel = n;
        }
        break;
    case ast.ConditionalDeclarationType.DebugSpecification:
    default: break;
    }
}

void genConditionalDeclaration(ast.ConditionalDeclaration decl, Module mod)
{
    final switch (decl.type) {
    case ast.ConditionalDeclarationType.Block:
        bool cond = genCondition(decl.condition, mod);
        if (cond) {
            foreach (declDef; decl.thenBlock) {
                genDeclarationDefinition(declDef, mod);
            }
        } else if (decl.elseBlock !is null) {
            foreach (declDef; decl.elseBlock) {
                genDeclarationDefinition(declDef, mod);
            }
        }
        break;
    case ast.ConditionalDeclarationType.AlwaysOn:
        mod.currentScope.topLevelBail = !genCondition(decl.condition, mod);
        break;
    case ast.ConditionalDeclarationType.VersionSpecification:        
    case ast.ConditionalDeclarationType.DebugSpecification:
        break;  // handled in declareConditionalDeclaration
    }
}

bool genCondition(ast.Condition condition, Module mod)
{
    final switch (condition.conditionType) {
    case ast.ConditionType.Version:
        return genVersionCondition(cast(ast.VersionCondition) condition.condition, mod);
    case ast.ConditionType.Debug:
        return genDebugCondition(cast(ast.DebugCondition) condition.condition, mod);
    case ast.ConditionType.StaticIf:
        return genStaticIfCondition(cast(ast.StaticIfCondition) condition.condition, mod);
    }
}

bool genVersionCondition(ast.VersionCondition condition, Module mod)
{
    final switch (condition.type) {
    case ast.VersionConditionType.Integer:
        auto i = extractIntegerLiteral(condition.integer);
        return i >= versionLevel;
    case ast.VersionConditionType.Identifier:
        auto ident = extractIdentifier(condition.identifier);
        return isVersionIdentifierSet(ident);
    case ast.VersionConditionType.Unittest:
        return unittestsEnabled;
    }
}

bool genDebugCondition(ast.DebugCondition condition, Module mod)
{
    final switch (condition.type) {
    case ast.DebugConditionType.Simple:
        return isDebug;
    case ast.DebugConditionType.Integer:
        auto i = extractIntegerLiteral(condition.integer);
        return i >= debugLevel;
    case ast.DebugConditionType.Identifier:
        auto ident = extractIdentifier(condition.identifier);
        return isDebugIdentifierSet(ident);
    }
}

bool genStaticIfCondition(ast.StaticIfCondition condition, Module mod)
{
    auto expr = genAssignExpression(condition.expression, mod);
    if (!expr.constant) {
        error(condition.expression.location, "expression inside of a static if must be known at compile time.");
    }
    return expr.constBool;
}
