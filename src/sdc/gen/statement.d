/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import std.conv;
import std.exception;

import llvm.c.Core;

import sdc.tokenstream;
import sdc.compilererror;
import sdc.source;
import sdc.lexer;
import sdc.util;
import sdc.global;
import ast = sdc.ast.all;
import sdc.gen.base;
import sdc.gen.cfg;
import sdc.gen.sdcmodule;
import sdc.gen.declaration;
import sdc.gen.expression;
import sdc.gen.value;
import sdc.gen.type;
import sdc.gen.sdcpragma;
import sdc.parser.declaration;
import sdc.parser.expression;
import sdc.parser.statement;
import sdc.extract.base;


void genBlockStatement(ast.BlockStatement blockStatement, Module mod)
{
    if (mod.currentFunction.cfgTail is null) {
        // Entry block.
        mod.currentFunction.cfgEntry = mod.currentFunction.cfgTail = new BasicBlock();
    }
    foreach (i, statement; blockStatement.statements) {
        genStatement(statement, mod);
    }
}

void genStatement(ast.Statement statement, Module mod)
{
    final switch (statement.type) {
    case ast.StatementType.Empty:
        break;
    case ast.StatementType.NonEmpty:
        genNonEmptyStatement(cast(ast.NonEmptyStatement) statement.node, mod);
        break;
    case ast.StatementType.Scope:
        genScopeStatement(cast(ast.ScopeStatement) statement.node, mod);
        break;
    }
}

void genScopeStatement(ast.ScopeStatement statement, Module mod)
{
    final switch (statement.type) {
    case ast.ScopeStatementType.NonEmpty:
        genNonEmptyStatement(cast(ast.NonEmptyStatement) statement.node, mod);
        break;
    case ast.ScopeStatementType.Block:
        genBlockStatement(cast(ast.BlockStatement) statement.node, mod);
        break;
    }
}

void genNoScopeNonEmptyStatement(ast.NoScopeNonEmptyStatement statement, Module mod)
{
    final switch (statement.type) {
    case ast.NoScopeNonEmptyStatementType.NonEmpty:
        genNonEmptyStatement(cast(ast.NonEmptyStatement) statement.node, mod);
        break;
    case ast.NoScopeNonEmptyStatementType.Block:
        genBlockStatement(cast(ast.BlockStatement) statement.node, mod);
        break;
    }
}

void genNoScopeStatement(ast.NoScopeStatement statement, Module mod)
{
    final switch (statement.type) with (ast.NoScopeStatementType) {
    case NonEmpty:
        genNonEmptyStatement(cast(ast.NonEmptyStatement) statement.node, mod);
        break;
    case Block:
        genBlockStatement(cast(ast.BlockStatement) statement.node, mod);
        break;
    case Empty:
        break;
    }
}

void genNonEmptyStatement(ast.NonEmptyStatement statement, Module mod)
{
    if (!mod.currentFunction.cfgEntry.canReachWithoutExit(mod.currentFunction.cfgTail)) {
        throw new CompilerError(statement.location, "statement is unreachable.");
    }
    switch (statement.type) {
    default:
        throw new CompilerPanic(statement.location, "unimplemented non empty statement type.");
        assert(false);
    case ast.NonEmptyStatementType.IfStatement:
        genIfStatement(cast(ast.IfStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.WhileStatement:
        genWhileStatement(cast(ast.WhileStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.ExpressionStatement:
        genExpressionStatement(cast(ast.ExpressionStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.DeclarationStatement:
        genDeclarationStatement(cast(ast.DeclarationStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.ReturnStatement:
        genReturnStatement(cast(ast.ReturnStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.ConditionalStatement:
        genConditionalStatement(cast(ast.ConditionalStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.PragmaStatement:
        genPragmaStatement(cast(ast.PragmaStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.MixinStatement:
        genMixinStatement(cast(ast.MixinStatement) statement.node, mod);
        break;
    }
}

void genMixinStatement(ast.MixinStatement statement, Module mod)
{
    auto val = genAssignExpression(statement.expression, mod);
    if (!val.isKnown || !isString(val.type)) {
        throw new CompilerError(statement.location, "a mixin statement must be a string known at compile time.");
    }
    auto source = new Source(val.knownString, val.location);
    auto tstream = lex(source);
    tstream.getToken();  // Skip BEGIN
    
    ast.Statement[] states;
    do {
        try {
            states ~= parseStatement(tstream);
        } catch (CompilerError) {
            break;
        }
    } while (true);
    
    foreach (state; states) {
        genStatement(state, mod);
    }
}

void genIfStatement(ast.IfStatement statement, Module mod)
{
    LLVMBasicBlockRef ifBB, elseBB;
    auto parent = mod.currentFunction.cfgTail;
    auto ifblock = new BasicBlock();
    auto ifout = new BasicBlock();
    parent.children ~= ifblock;
    
    mod.pushScope();
    genIfCondition(statement.ifCondition, mod, ifBB, elseBB);
    auto endifBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "endif");
    LLVMPositionBuilderAtEnd(mod.builder, ifBB);
    
    mod.currentFunction.cfgTail = ifblock;
    genThenStatement(statement.thenStatement, mod);
    
    if (!mod.currentFunction.cfgTail.isExitBlock) {
        LLVMBuildBr(mod.builder, endifBB);
    }
    mod.popScope();
    
    LLVMPositionBuilderAtEnd(mod.builder, elseBB);
    if (statement.elseStatement !is null) {
        mod.pushScope();
        
        auto elseblock = new BasicBlock();
        parent.children ~= elseblock;
                
        mod.currentFunction.cfgTail = elseblock;
        genElseStatement(statement.elseStatement, mod);
        if (!mod.currentFunction.cfgTail.isExitBlock) {
            LLVMBuildBr(mod.builder, endifBB);
        }
        if (elseblock.children.length == 0) {
            elseblock.children ~= ifout;
            ifblock.children ~= ifout;
            mod.currentFunction.cfgTail = ifout;
        } else {
            ifblock.children ~= mod.currentFunction.cfgTail;
        }
        mod.popScope();
    } else {
        parent.children ~= ifout;
        mod.currentFunction.cfgTail = ifout;
        LLVMBuildBr(mod.builder, endifBB);
    }
    
    
    LLVMPositionBuilderAtEnd(mod.builder, endifBB);
}

void genIfCondition(ast.IfCondition condition, Module mod, ref LLVMBasicBlockRef ifBB, ref LLVMBasicBlockRef elseBB)
{ 
    auto expr = genExpression(condition.expression, mod);
    
    final switch (condition.type) {
    case ast.IfConditionType.ExpressionOnly:
        break;
    case ast.IfConditionType.Identifier:
    case ast.IfConditionType.Declarator:
        throw new CompilerPanic("unimplemented if condition type.");
    }
    
    ifBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "iftrue");
    elseBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "else");
    LLVMBuildCondBr(mod.builder, expr.get(), ifBB, elseBB);
}

void genThenStatement(ast.ThenStatement statement, Module mod)
{
    genScopeStatement(statement.statement, mod);
}

void genElseStatement(ast.ElseStatement statement, Module mod)
{
    genScopeStatement(statement.statement, mod);
}

void genWhileStatement(ast.WhileStatement statement, Module mod)
{    
    auto looptopBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "looptop");
    auto loopbodyBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopbody");
    auto loopendBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopend");
    
    auto parent  = mod.currentFunction.cfgTail;
    auto looptop = new BasicBlock();
    auto loopout = new BasicBlock();
    parent.children ~= looptop;
    parent.children ~= loopout;
    looptop.children ~= loopout;
    looptop.children ~= looptop;

    LLVMBuildBr(mod.builder, looptopBB);
    mod.pushScope();
    LLVMPositionBuilderAtEnd(mod.builder, looptopBB);
    auto expr = genExpression(statement.expression, mod);
    LLVMBuildCondBr(mod.builder, expr.get(), loopbodyBB, loopendBB);
    LLVMPositionBuilderAtEnd(mod.builder, loopbodyBB);
    
    mod.currentFunction.cfgTail = looptop;
    genScopeStatement(statement.statement, mod);
    if (!mod.currentFunction.cfgTail.isExitBlock) {
        LLVMBuildBr(mod.builder, looptopBB);
    }
            
    mod.currentFunction.cfgTail = loopout;
    mod.popScope();
    LLVMPositionBuilderAtEnd(mod.builder, loopendBB);
}

void genExpressionStatement(ast.ExpressionStatement statement, Module mod)
{
    genExpression(statement.expression, mod);
}

void genDeclarationStatement(ast.DeclarationStatement statement, Module mod)
{
    genDeclaration(statement.declaration, mod);
}

void genReturnStatement(ast.ReturnStatement statement, Module mod)
{
    mod.currentFunction.cfgTail.isExitBlock = true;
    auto t = mod.currentFunction.type.returnType;
    if (t.dtype == DType.Void) {
        LLVMBuildRetVoid(mod.builder);
        return; 
    }
    
    if (mod.inferringFunction && statement.expression is null) {
        throw new InferredTypeFoundException(new VoidType(mod));
    }
    
    auto val = genExpression(statement.expression, mod);
    
    if (mod.inferringFunction) {
        throw new InferredTypeFoundException(val.type);
    }
    
    val = implicitCast(val.location, val, t);
    LLVMBuildRet(mod.builder, val.get());
}

void genConditionalStatement(ast.ConditionalStatement statement, Module mod)
{
    if (genCondition(statement.condition, mod)) {
        genNoScopeNonEmptyStatement(statement.thenStatement, mod);
    } else {
        if (statement.elseStatement !is null) {
            genNoScopeNonEmptyStatement(statement.elseStatement, mod);
        }
    }
}

void genPragmaStatement(ast.PragmaStatement statement, Module mod)
{
    genPragma(statement.thePragma, mod);
    genNoScopeStatement(statement.statement, mod);
}
