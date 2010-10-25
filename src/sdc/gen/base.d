/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.array;
import std.conv;
import std.exception;
import std.string;

import sdc.compilererror;
import sdc.util;
import sdc.global;
import ast = sdc.ast.all;
import sdc.extract.base;
import sdc.gen.sdcmodule;
import sdc.gen.sdcimport;
import sdc.gen.declaration;
import sdc.gen.expression;
import sdc.gen.type;
import sdc.gen.aggregate;
import sdc.gen.attribute;


bool canGenDeclarationDefinition(ast.DeclarationDefinition declDef, Module mod)
{
    switch (declDef.type) with (ast) {
    case DeclarationDefinitionType.Declaration:
        return canGenDeclaration(cast(Declaration) declDef.node, mod);
    case DeclarationDefinitionType.ImportDeclaration:
        return canGenImportDeclaration(cast(ImportDeclaration) declDef.node, mod);
    case ast.DeclarationDefinitionType.ConditionalDeclaration:
        return true;  // TODO
    case ast.DeclarationDefinitionType.AggregateDeclaration:
        return canGenAggregateDeclaration(cast(ast.AggregateDeclaration) declDef.node, mod);
    case ast.DeclarationDefinitionType.AttributeSpecifier:
        return canGenAttributeSpecifier(cast(ast.AttributeSpecifier) declDef.node, mod);
    default:
        return false;
    }
    assert(false);
}

Module genModule(ast.Module astModule)
{
    auto mod = new Module(astModule.moduleDeclaration.name);
    genModuleAndPackages(mod);
    resolveDeclarationDefinitionList(astModule.declarationDefinitions, mod);
    return mod;
}

void genModuleAndPackages(Module mod)
{
    Scope parentScope = mod.currentScope;
    foreach (i, identifier; mod.name.identifiers) {
        if (i < mod.name.identifiers.length - 1) {
            // Package.
            auto name = extractIdentifier(identifier);
            auto _scope = new Scope();
            parentScope.add(name, new Store(_scope));
            parentScope = _scope;
        } else {
            // Module.
            auto name = extractIdentifier(identifier);
            auto store = new Store(mod.currentScope);
            parentScope.add(name, store);
        }
    }
}

void resolveDeclarationDefinitionList(ast.DeclarationDefinition[] list, Module mod)
{
    auto resolutionList = list.dup;
    int stillToGo, oldStillToGo = -1;
    foreach (d; resolutionList) {
        d.parentName = mod.name;
        d.importedSymbol = false;
        d.buildStage = ast.BuildStage.Unhandled;
    }
    //genConditionals(resolutionList, mod);
    foreach (df; implicitDeclDefs) {
        resolutionList ~= df;
    }
    bool finalPass;
    do {
        foreach (declDef; resolutionList) {
            genDeclarationDefinition(declDef, mod);
        }
        
        stillToGo = 0;
        foreach (i, declDef; resolutionList) with (declDef) {
            if (buildStage == ast.BuildStage.Deferred || buildStage == ast.BuildStage.Unhandled ||
                buildStage == ast.BuildStage.ReadyToExpand || buildStage == ast.BuildStage.ReadyToRecurse) {
                stillToGo++;
            }
        }
        
        // Let's figure out if we can leave.
        if (stillToGo == 0) {
            break;
        } else if (stillToGo == oldStillToGo) {
            // Uh-oh.. nothing new was resolved... look for things we can expand.
            ast.DeclarationDefinition[] toAppend;
            foreach (declDef; resolutionList) {
                if (declDef.buildStage == ast.BuildStage.ReadyToExpand) {
                    toAppend ~= expand(declDef, mod);
                }
                foreach (d; toAppend) if (d.buildStage != ast.BuildStage.DoneForever) {
                    d.buildStage = ast.BuildStage.Unhandled;
                }
            }
            if (toAppend.length > 0) {
                resolutionList ~= toAppend;
            } else {
                if (!finalPass) {
                    finalPass = true;
                    continue;
                }
                throw new CompilerPanic(resolutionList[$ - 1].location, "module compilation failure.");
            }
        }
        oldStillToGo = stillToGo;
    } while (true);
    
    // Okay. Build ze functions!
    foreach (declDef; mod.functionBuildList) {
        if (declDef.buildStage != ast.BuildStage.ReadyForCodegen || declDef.importedSymbol) {
            continue;
        }
        assert(declDef.type == ast.DeclarationDefinitionType.Declaration);
        genDeclaration(cast(ast.Declaration) declDef.node, mod);
    }
}

ast.DeclarationDefinition[] expand(ast.DeclarationDefinition declDef, Module mod)
{
    declDef.buildStage = ast.BuildStage.Done;
    switch (declDef.type) {
    case ast.DeclarationDefinitionType.AttributeSpecifier:
        auto specifier = cast(ast.AttributeSpecifier) declDef.node;
        assert(specifier);
        if (specifier.declarationBlock is null) {
            throw new CompilerPanic(declDef.location, "attempted to expand non declaration block containing attribute specifier.");
        }
        auto list = specifier.declarationBlock.declarationDefinitions.dup;
        foreach (e; list) {
            e.attributes ~= specifier.attribute;
        }
        return list;
    case ast.DeclarationDefinitionType.ConditionalDeclaration:
        auto decl = enforce(cast(ast.ConditionalDeclaration) declDef.node);
        bool cond = genCondition(decl.condition, mod);
        ast.DeclarationDefinition[] newTopLevels;
        if (cond) {
            foreach (declDef_; decl.thenBlock.declarationDefinitions) {
                newTopLevels ~= declDef_;
            }
        } else if (decl.elseBlock !is null) {
            foreach (declDef_; decl.elseBlock.declarationDefinitions) {
                newTopLevels ~= declDef_;
            }
        }
        return newTopLevels;
    default:
        throw new CompilerPanic(declDef.location, "attempted to expand non expandable declaration definition.");
    }
    assert(false);
}

void genDeclarationDefinition(ast.DeclarationDefinition declDef, Module mod)
{
    with (declDef) with (ast.BuildStage)
    if (buildStage != Unhandled && buildStage != Deferred) {
        return;
    }
    
    foreach (attribute; declDef.attributes) {
        switch (attribute.type) with (ast.AttributeType) {
        case ExternC:
            mod.currentLinkage = ast.Linkage.ExternC;
            break;
        case ExternD:
            mod.currentLinkage = ast.Linkage.ExternD;
            break;
        case Private:
            mod.currentAccess = ast.Access.Private;
            break;
        case Protected:
            mod.currentAccess = ast.Access.Protected;
            break;
        case Package:
            mod.currentAccess = ast.Access.Package;
            break;
        case Export:
            mod.currentAccess = ast.Access.Export;
            break;
        case Public:
            mod.currentAccess = ast.Access.Public;
            break;
        default:
            throw new CompilerPanic(attribute.location, format("unhandled attribute type '%s'.", to!string(attribute.type)));
        }
    }
    
    switch (declDef.type) {
    case ast.DeclarationDefinitionType.Declaration:
        auto decl = cast(ast.Declaration) declDef.node;
        assert(decl);
        auto can = canGenDeclaration(decl, mod);        
        if (can) {
            if (decl.type != ast.DeclarationType.Function) {
                declareDeclaration(decl, mod);
                genDeclaration(decl, mod);
                declDef.buildStage = ast.BuildStage.Done;
            } else {
                declareDeclaration(decl, mod);
                declDef.buildStage = ast.BuildStage.ReadyForCodegen;
                mod.functionBuildList ~= declDef;
            }
        } else {
            declDef.buildStage = ast.BuildStage.Deferred;
        }
        break;
    case ast.DeclarationDefinitionType.ImportDeclaration:
        declDef.buildStage = ast.BuildStage.Done;
        genImportDeclaration(cast(ast.ImportDeclaration) declDef.node, mod);
        break;
    case ast.DeclarationDefinitionType.AggregateDeclaration:
        auto can = canGenAggregateDeclaration(cast(ast.AggregateDeclaration) declDef.node, mod);
        if (can) {
            genAggregateDeclaration(cast(ast.AggregateDeclaration) declDef.node, mod);
            declDef.buildStage = ast.BuildStage.Done;
        } else {
            declDef.buildStage = ast.BuildStage.Deferred;
        }
        break;
    case ast.DeclarationDefinitionType.AttributeSpecifier:
        auto can = canGenAttributeSpecifier(cast(ast.AttributeSpecifier) declDef.node, mod);
        if (can) {
            declDef.buildStage = ast.BuildStage.ReadyToExpand;
        } else {
            declDef.buildStage = ast.BuildStage.Deferred;
        }
        break;
    case ast.DeclarationDefinitionType.ConditionalDeclaration:
        genConditionalDeclaration(declDef, cast(ast.ConditionalDeclaration) declDef.node, mod);
        break;
    default:
        throw new CompilerPanic(declDef.location, format("unhandled DeclarationDefinition '%s'", to!string(declDef.type)));
    }
}


void genConditionalDeclaration(ast.DeclarationDefinition declDef, ast.ConditionalDeclaration decl, Module mod)
{
    final switch (decl.type) {
    case ast.ConditionalDeclarationType.Block:    
        declDef.buildStage = ast.BuildStage.ReadyToExpand;
        break;
    case ast.ConditionalDeclarationType.VersionSpecification:        
        declDef.buildStage = ast.BuildStage.Done;
        auto spec = cast(ast.VersionSpecification) decl.specification;
        auto ident = extractIdentifier(cast(ast.Identifier) spec.node);
        if (mod.hasVersionBeenTested(ident)) {
            throw new CompilerError(spec.location, format("specification of '%s' after use is not allowed.", ident));
        }
        mod.setVersion(decl.location, ident);
        break;
    case ast.ConditionalDeclarationType.DebugSpecification:
        declDef.buildStage = ast.BuildStage.Done;
        auto spec = cast(ast.DebugSpecification) decl.specification;
        auto ident = extractIdentifier(cast(ast.Identifier) spec.node);
        if (mod.hasDebugBeenTested(ident)) {
            throw new CompilerError(spec.location, format("specification of '%s' after use is not allowed.", ident));
        }
        mod.setDebug(decl.location, ident);
        break;
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
    case ast.VersionConditionType.Identifier:
        auto ident = extractIdentifier(condition.identifier);
        return mod.isVersionSet(ident);
    case ast.VersionConditionType.Unittest:
        return unittestsEnabled;
    }
}

bool genDebugCondition(ast.DebugCondition condition, Module mod)
{
    final switch (condition.type) {
    case ast.DebugConditionType.Simple:
        return isDebug;
    case ast.DebugConditionType.Identifier:
        auto ident = extractIdentifier(condition.identifier);
        return mod.isDebugSet(ident);
    }
}

bool genStaticIfCondition(ast.StaticIfCondition condition, Module mod)
{
    auto expr = genAssignExpression(condition.expression, mod);
    if (!expr.constant) {
        throw new CompilerError(condition.expression.location, "expression inside of a static if must be known at compile time.");
    }
    return expr.constBool;
}

