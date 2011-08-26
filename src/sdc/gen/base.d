/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.array;
import std.algorithm;
import std.conv;
import std.exception;
import std.string;

import sdc.compilererror;
import sdc.util;
import sdc.extract;
import sdc.global;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.sdcimport;
import sdc.gen.sdcclass;
import sdc.gen.declaration;
import sdc.gen.expression;
import sdc.gen.type;
import sdc.gen.aggregate;
import sdc.gen.attribute;
import sdc.gen.enumeration;
import sdc.gen.sdctemplate;


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
    case ast.DeclarationDefinitionType.TemplateDeclaration:
        return true;  // TODO
    case ast.DeclarationDefinitionType.ClassDeclaration:
        return canGenClassDeclaration(cast(ast.ClassDeclaration) declDef.node, mod);
    case ast.DeclarationDefinitionType.EnumDeclaration:
        return true;  // TODO
    default:
        return false;
    }
    assert(false);
}

Module genModule(ast.Module astModule, TranslationUnit tu)
{
    auto mod = new Module(astModule.moduleDeclaration.name);
    mod.translationUnit = tu;
    genModuleAndPackages(mod);

    auto name = extractQualifiedName(mod.name);
    verbosePrint("Generating module '" ~ name ~ "'.", VerbosePrintColour.Red);
    verboseIndent++;

    resolveDeclarationDefinitionList(astModule.declarationDefinitions, mod, null);

    verboseIndent--;
    verbosePrint("Done generating '" ~ name ~ "'.", VerbosePrintColour.Red);

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
            parentScope.add(name, new Store(_scope, mod.name.location));
            parentScope = _scope;
        } else {
            // Module.
            auto name = extractIdentifier(identifier);
            auto store = new Store(mod.currentScope, mod.name.location);
            parentScope.add(name, store);
        }
    }
}

void resolveDeclarationDefinitionList(ast.DeclarationDefinition[] list, Module mod, Type parentType)
{
    auto resolutionList = list.dup;
    size_t tmp, oldStillToGo;
    size_t* stillToGo = parentType is null ? &tmp : &parentType.stillToGo;
    assert(stillToGo);

    foreach (d; resolutionList) {
        d.parentName = mod.name;
        d.importedSymbol = false;
        d.buildStage = ast.BuildStage.Unhandled;
    }
    bool finalPass;
    do {
        foreach (declDef; resolutionList) {
            declDef.parentType = parentType;
            genDeclarationDefinition(declDef, mod, *stillToGo);
        }
        
        *stillToGo = count!"a.buildStage < b"(resolutionList, ast.BuildStage.ReadyForCodegen);
        
        // Let's figure out if we can leave.
        if (*stillToGo == 0) {
            break;
        } else if (*stillToGo == oldStillToGo) {
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
                foreach (tu; getTranslationUnits()) {
                    if (tu.gModule is null && tu.compile && tu !is mod.translationUnit) {
                        tu.gModule = genModule(tu.aModule, tu);
                    }
                }
                if (!finalPass) {
                    finalPass = true;
                    continue;
                }
                // Module compilation failed.
                if (mod.lookupFailures.length > 0) {
                    auto failure = mod.lookupFailures[$ - 1];
                    throw new CompilerError(failure.location, format("type '%s' is undefined.", failure.name));
                } else {
                    throw new CompilerPanic("module compilation failure.");
                }
            }
        }
        oldStillToGo = *stillToGo;
    } while (true);
}

ast.DeclarationDefinition[] expand(ast.DeclarationDefinition declDef, Module mod)
{
    declDef.buildStage = ast.BuildStage.Done;
    switch (declDef.type) {
    case ast.DeclarationDefinitionType.ConditionalDeclaration:
        auto decl = enforce(cast(ast.ConditionalDeclaration) declDef.node);
        bool cond = genCondition(decl.condition, mod);
        ast.DeclarationDefinition[] newTopLevels;
        if (cond) {
            foreach (declDef_; decl.thenBlock) {
                newTopLevels ~= declDef_;
            }
        } else if (decl.elseBlock !is null) {
            foreach (declDef_; decl.elseBlock) {
                newTopLevels ~= declDef_;
            }
        }
        return newTopLevels;
    default:
        throw new CompilerPanic(declDef.location, "attempted to expand non expandable declaration definition.");
    }
    assert(false);
}

void genDeclarationDefinition(ast.DeclarationDefinition declDef, Module mod, size_t stillToGo)
{
    with (declDef) with (ast.BuildStage)
    if (buildStage != Unhandled && buildStage != Deferred) {
        return;
    }
    
    switch (declDef.type) {
    case ast.DeclarationDefinitionType.Declaration:
        auto decl = cast(ast.Declaration) declDef.node;
        assert(decl);
        auto can = canGenDeclaration(decl, mod);        
        if (can) {
            if (decl.type != ast.DeclarationType.Function) {
                declareDeclaration(decl, declDef, mod);
                genDeclaration(decl, declDef, mod);
                declDef.buildStage = ast.BuildStage.Done;
            } else {
                declareDeclaration(decl, declDef, mod);
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
        auto asAggregate = cast(ast.AggregateDeclaration) declDef.node;
        auto can = canGenAggregateDeclaration(asAggregate, mod);
        if (!can) with (ast.BuildStage) {
            if (declDef.buildStage == Unhandled) {
                declDef.buildStage = Deferred;
                break;
            }
            assert(asAggregate.structBody !is null);
            if (stillToGo > 0 && stillToGo > asAggregate.structBody.declarations.length) {
                declDef.buildStage = Deferred;
                break;
            }
        }
        genAggregateDeclaration(asAggregate, declDef, mod);
        declDef.buildStage = ast.BuildStage.Done;
        break;
    case ast.DeclarationDefinitionType.ClassDeclaration:
        genClassDeclaration(cast(ast.ClassDeclaration) declDef.node, mod);
        declDef.buildStage = ast.BuildStage.Done;
        break;
    case ast.DeclarationDefinitionType.ConditionalDeclaration:
        genConditionalDeclaration(declDef, cast(ast.ConditionalDeclaration) declDef.node, mod);
        break;
    case ast.DeclarationDefinitionType.EnumDeclaration:
        genEnumDeclaration(cast(ast.EnumDeclaration) declDef.node, mod);
        declDef.buildStage = ast.BuildStage.Done;
        break;
    case ast.DeclarationDefinitionType.TemplateDeclaration:
        genTemplateDeclaration(cast(ast.TemplateDeclaration) declDef.node, mod);
        declDef.buildStage = ast.BuildStage.Done;
        break;
    case ast.DeclarationDefinitionType.StaticAssert:
        genStaticAssert(cast(ast.StaticAssert)declDef.node, mod);
        declDef.buildStage = ast.BuildStage.Done;
        break;
    case ast.DeclarationDefinitionType.Unittest:
        declDef.buildStage = ast.BuildStage.Done;
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
    if (!expr.isKnown) {
        throw new CompilerError(condition.expression.location, "expression inside of a static if must be known at compile time.");
    }
    return expr.knownBool; // TODO: unsafe!!!
}

void genStaticAssert(ast.StaticAssert staticAssert, Module mod)
{
    static immutable unknownExprError = "expression inside of a static assert must be known at compile time."; 
    auto condition = genAssignExpression(staticAssert.condition, mod);
    if (!condition.isKnown) {
        throw new CompilerError(condition.location, unknownExprError);
    }
    
    string message;
    if (staticAssert.message !is null) {
        auto messageExpr = genAssignExpression(staticAssert.message, mod);
        if(!messageExpr.isKnown) {
            throw new CompilerError(condition.location, unknownExprError);
        }
        
        message = messageExpr.knownString; // TODO: unsafe!!!
    } else {
        message = "static assert failed";
    }
    
    if (!condition.knownBool) { // TODO: unsafe!!!
        throw new CompilerError(staticAssert.location, message);
    }
}