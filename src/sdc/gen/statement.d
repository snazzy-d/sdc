/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;
import core.runtime;

import llvm.c.Core;

import sdc.compilererror;
import sdc.source;
import sdc.lexer;
import sdc.util;
import sdc.global;
import sdc.extract;
import ast = sdc.ast.all;
import sdc.gen.base;
import sdc.gen.cfg;
import sdc.gen.sdcmodule;
import sdc.gen.declaration;
import sdc.gen.expression;
import sdc.gen.value;
import sdc.gen.type;
import sdc.gen.sdcpragma;
import sdc.gen.sdcfunction;
import sdc.parser.declaration;
import sdc.parser.expression;
import sdc.parser.statement;



void genBlockStatement(ast.BlockStatement blockStatement, Module mod)
{
    if (mod.currentFunction.cfgTail is null) {
        // Entry block.
        mod.currentFunction.cfgEntry = mod.currentFunction.cfgTail = new BasicBlock("block");
    }
    foreach (i, statement; blockStatement.statements) {
        genStatement(statement, mod);
    }
}

void genStatement(ast.Statement statement, Module mod)
{
    if (!mod.currentFunction.cfgEntry.canReach(mod.currentFunction.cfgTail)) {
        warning(statement.location, "statement is unreachable.");
    }
    switch (statement.type) {
    default:
        throw new CompilerPanic(statement.location, "unimplemented non empty statement type.");
        assert(false);
    case ast.StatementType.BlockStatement:
        genBlockStatement(cast(ast.BlockStatement) statement.node, mod);
        break;
    case ast.StatementType.IfStatement:
        genIfStatement(cast(ast.IfStatement) statement.node, mod);
        break;
    case ast.StatementType.WhileStatement:
        genWhileStatement(cast(ast.WhileStatement) statement.node, mod);
        break;
    case ast.StatementType.ExpressionStatement:
        genExpressionStatement(cast(ast.ExpressionStatement) statement.node, mod);
        break;
    case ast.StatementType.DeclarationStatement:
        genDeclarationStatement(cast(ast.DeclarationStatement) statement.node, mod);
        break;
    case ast.StatementType.ReturnStatement:
        genReturnStatement(cast(ast.ReturnStatement) statement.node, mod);
        break;
    case ast.StatementType.ConditionalStatement:
        genConditionalStatement(cast(ast.ConditionalStatement) statement.node, mod);
        break;
    case ast.StatementType.PragmaStatement:
        genPragmaStatement(cast(ast.PragmaStatement) statement.node, mod);
        break;
    case ast.StatementType.MixinStatement:
        genMixinStatement(cast(ast.MixinStatement) statement.node, mod);
        break;
    case ast.StatementType.ThrowStatement:
        genThrowStatement(cast(ast.ThrowStatement) statement.node, mod);
        break;
    case ast.StatementType.TryStatement:
        genTryStatement(cast(ast.TryStatement) statement.node, mod);
        break;
    case ast.StatementType.LabeledStatement:
        genLabeledStatement(cast(ast.LabeledStatement) statement.node, mod);
        break;
    case ast.StatementType.GotoStatement:
        genGotoStatement(cast(ast.GotoStatement) statement.node, mod);
        break;
    case ast.StatementType.StaticAssert:
        genStaticAssert(cast(ast.StaticAssert) statement.node, mod);
        break;
    }
}

void genGotoStatement(ast.GotoStatement statement, Module mod)
{
    auto parent = mod.currentFunction.cfgTail;
    parent.fallsThrough = false;
    
    final switch (statement.type) {
    case ast.GotoStatementType.Identifier:
        auto name = extractIdentifier(statement.identifier);
        auto p = name in mod.currentFunction.labels;
        if (p is null) {
            mod.currentFunction.pendingGotos ~= PendingGoto(statement.location, name, mod.currentFunction.currentBasicBlock, parent);
            break;
        }
        parent.children ~= p.block;
        LLVMBuildBr(mod.builder, p.bb);
        break;
    case ast.GotoStatementType.Case:
        throw new CompilerPanic(statement.location, "goto case is unimplemented.");
    case ast.GotoStatementType.Default:
        throw new CompilerPanic(statement.location, "goto default is unimplemented.");
    }
}

void genLabeledStatement(ast.LabeledStatement statement, Module mod)
{
    auto name = extractIdentifier(statement.identifier);
    
    auto block = new BasicBlock(name);
    auto parent = mod.currentFunction.cfgTail;
    parent.children ~= block;
    mod.currentFunction.cfgTail = block;
    
    auto bb = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, toStringz(name));
    LLVMBuildBr(mod.builder, bb);
    if (auto p = name in mod.currentFunction.labels) {
        throw new CompilerError(statement.location, "redefinition of label '" ~ name ~ "'.",
            new CompilerError(p.location, "first defined here.")
        );
    }
    mod.currentFunction.labels[name] = Label(statement.location, block, bb);
    
    auto pendingGotos = mod.currentFunction.pendingGotos;
    while (!pendingGotos.empty) {
        auto pending = mod.currentFunction.pendingGotos.front;
        if (pending.label == name) {
            pendingGotos.popFront;
            mod.currentFunction.pendingGotos.popFront;
            LLVMPositionBuilderAtEnd(mod.builder, pending.insertAt);
            auto exitsToBlock = find(pending.block.children, block);
            if (exitsToBlock.empty) {
                LLVMBuildBr(mod.builder, bb);
            }
            pending.block.children ~= block;
        } else {
            pendingGotos.popFront;
        }
    }
    
    LLVMPositionBuilderAtEnd(mod.builder, bb);
    mod.currentFunction.currentBasicBlock = bb;
    genStatement(statement.statement, mod);
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
    auto ifblock = new BasicBlock("if");
    auto ifout = new BasicBlock("else");
    parent.children ~= ifblock;
    
    mod.pushScope();
    genIfCondition(statement.ifCondition, mod, ifBB, elseBB);
    auto endifBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "endif");
    LLVMPositionBuilderAtEnd(mod.builder, ifBB);
    mod.currentFunction.currentBasicBlock = ifBB;
    
    mod.currentFunction.cfgTail = ifblock;
    genThenStatement(statement.thenStatement, mod);
    
    if (mod.currentFunction.cfgTail.fallsThrough) {
        LLVMBuildBr(mod.builder, endifBB);
    }
    mod.popScope();
    
    LLVMPositionBuilderAtEnd(mod.builder, elseBB);
    mod.currentFunction.currentBasicBlock = elseBB;
    if (statement.elseStatement !is null) {
        mod.pushScope();
        
        auto elseblock = new BasicBlock("elseblock");
        parent.children ~= elseblock;
                
        mod.currentFunction.cfgTail = elseblock;
        genElseStatement(statement.elseStatement, mod);
        if (mod.currentFunction.cfgTail.fallsThrough) {
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
    mod.currentFunction.currentBasicBlock = endifBB;
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
    genStatement(statement.statement, mod);
}

void genElseStatement(ast.ElseStatement statement, Module mod)
{
    genStatement(statement.statement, mod);
}

void genWhileStatement(ast.WhileStatement statement, Module mod)
{    
    auto looptopBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "looptop");
    auto loopbodyBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopbody");
    auto loopendBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopend");
    
    auto parent  = mod.currentFunction.cfgTail;
    auto looptop = new BasicBlock("whiletop");
    auto loopout = new BasicBlock("whileout");
    parent.children ~= looptop;
    parent.children ~= loopout;
    looptop.children ~= loopout;
    looptop.children ~= looptop;

    LLVMBuildBr(mod.builder, looptopBB);
    mod.pushScope();
    LLVMPositionBuilderAtEnd(mod.builder, looptopBB);
    mod.currentFunction.currentBasicBlock = looptopBB;
    auto expr = genExpression(statement.expression, mod);
    LLVMBuildCondBr(mod.builder, expr.get(), loopbodyBB, loopendBB);
    LLVMPositionBuilderAtEnd(mod.builder, loopbodyBB);
    mod.currentFunction.currentBasicBlock = loopbodyBB;
    
    mod.currentFunction.cfgTail = looptop;
    genStatement(statement.statement, mod);
    if (mod.currentFunction.cfgTail.fallsThrough) {
        LLVMBuildBr(mod.builder, looptopBB);
    }
            
    mod.currentFunction.cfgTail = loopout;
    mod.popScope();
    LLVMPositionBuilderAtEnd(mod.builder, loopendBB);
    mod.currentFunction.currentBasicBlock = loopendBB;
}

void genExpressionStatement(ast.ExpressionStatement statement, Module mod)
{
    genExpression(statement.expression, mod);
}

void genDeclarationStatement(ast.DeclarationStatement statement, Module mod)
{
    declareDeclaration(statement.declaration, null, mod);
    genDeclaration(statement.declaration, null, mod);
}

void genReturnStatement(ast.ReturnStatement statement, Module mod)
{
    mod.currentFunction.cfgTail.isExitBlock = true;
    auto t = mod.currentFunction.type.returnType;
    if (t.dtype == DType.Void) {
        LLVMBuildRetVoid(mod.builder);
        return; 
    }
    
    auto val = genExpression(statement.expression, mod);
    
    val = implicitCast(val.location, val, t);
    LLVMBuildRet(mod.builder, val.get());
}

void genTryStatement(ast.TryStatement statement, Module mod)
{
    auto parent = mod.currentFunction.cfgTail;
    auto tryB   = new BasicBlock("try");
    auto catchB = new BasicBlock("catch");
    auto outB   = new BasicBlock("tryout");
    parent.children ~= tryB;
    tryB.children ~= catchB;
    
    auto catchBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "catch");
    auto outBB   = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "out");
    mod.catchTargetStack ~= CatchTargets(catchBB, catchB);

    mod.currentFunction.cfgTail = tryB;
    genStatement(statement.statement, mod);
    if (mod.currentFunction.cfgTail.fallsThrough) {
        LLVMBuildBr(mod.builder, outBB);
    }
    mod.currentFunction.cfgTail.children ~= outB;
    mod.catchTargetStack = mod.catchTargetStack[0 .. $ - 1];
    
    mod.currentFunction.cfgTail = catchB;
    LLVMPositionBuilderAtEnd(mod.builder, catchBB);
    mod.currentFunction.currentBasicBlock = catchBB;
    genStatement(statement.catchStatement, mod);
    if (mod.currentFunction.cfgTail.fallsThrough) {
        LLVMBuildBr(mod.builder, outBB);
    }
    mod.currentFunction.cfgTail.children ~= outB;
    
    mod.currentFunction.cfgTail = outB;
    LLVMPositionBuilderAtEnd(mod.builder, outBB);
    mod.currentFunction.currentBasicBlock = outBB;
}

void genThrowStatement(ast.ThrowStatement statement, Module mod)
{
    mod.currentFunction.cfgTail.isExitBlock = true;
    auto expression = genExpression(statement.expression, mod);
    if (expression.type.dtype != DType.Class) {
        throw new CompilerError(expression.location, "can only throw class instances.");
    }
    LLVMBuildUnwind(mod.builder);
}

void genConditionalStatement(ast.ConditionalStatement statement, Module mod)
{
    if (genCondition(statement.condition, mod)) {
        genStatement(statement.thenStatement, mod);
    } else {
        if (statement.elseStatement !is null) {
            genStatement(statement.elseStatement, mod);
        }
    }
}

void genPragmaStatement(ast.PragmaStatement statement, Module mod)
{
    genPragma(statement.thePragma, mod);
    
    if (statement.statement !is null) {
        genStatement(statement.statement, mod);
    }
}
