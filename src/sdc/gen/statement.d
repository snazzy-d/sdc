/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2011 Jakob Ovrum.
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
import sdc.lexer;
import sdc.util;
import sdc.aglobal;
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
import sdc.gen.sdcswitch;
import sdc.gen.loop;
import sdc.parser.declaration;
import sdc.parser.expression;
import sdc.parser.statement;


// Called for return, break, continue and throw.
// TODO: goto?
private void declareExitBlock(string name, Module mod)
{
    name = "post" ~ name;
    mod.currentFunction.cfgTail.isExitBlock = true;
    mod.currentFunction.cfgTail = new BasicBlock(name);
    
    auto bb = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, toStringz(name));
    LLVMPositionBuilderAtEnd(mod.builder, bb);
    mod.currentFunction.currentBasicBlock = bb;
}

void genBlockStatement(ast.BlockStatement blockStatement, Module mod)
{
    if (mod.currentFunction.cfgTail is null) {
        // Entry block.
        mod.currentFunction.cfgEntry = mod.currentFunction.cfgTail = new BasicBlock("entry");
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
        throw new CompilerPanic(statement.location, "unimplemented statement type.");
    case ast.StatementType.EmptyStatement:
        break;
    case ast.StatementType.BlockStatement:
        genBlockStatement(cast(ast.BlockStatement) statement.node, mod);
        break;
    case ast.StatementType.IfStatement:
        genIfStatement(cast(ast.IfStatement) statement.node, mod);
        break;
    case ast.StatementType.WhileStatement:
        genWhileStatement(cast(ast.WhileStatement) statement.node, mod);
        break;
    case ast.StatementType.DoStatement:
        genDoStatement(cast(ast.DoStatement) statement.node, mod);
        break;
    case ast.StatementType.ForStatement:
        genForStatement(cast(ast.ForStatement) statement.node, mod);
        break;
    case ast.StatementType.ForeachStatement:
        auto asForeach = cast(ast.ForeachStatement) statement.node;
        if (asForeach.form == ast.ForeachForm.Range) {
            genForeachRangeStatement(asForeach, mod);
        } else {
            genForeachStatement(asForeach, mod);
        }
        break;
    case ast.StatementType.BreakStatement:
        genBreakStatement(cast(ast.BreakStatement) statement.node, mod);
        break;
    case ast.StatementType.ContinueStatement:
        genContinueStatement(cast(ast.ContinueStatement) statement.node, mod);
        break;
    case ast.StatementType.SwitchStatement:
        genSwitchStatement(cast(ast.SwitchStatement) statement.node, mod);
        break;
    case ast.StatementType.CaseStatement:
        genCaseStatement(cast(ast.CaseListStatement) statement.node, mod);
        break;
    case ast.StatementType.CaseRangeStatement:
        genCaseRangeStatement(cast(ast.CaseRangeStatement) statement.node, mod);
        break;
    case ast.StatementType.DefaultStatement:
        genDefaultStatement(cast(ast.SwitchSubStatement) statement.node, mod);
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
        auto name = extractIdentifier(statement.target);
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
    auto val = genConditionalExpression(statement.code, mod);
    if (!val.isKnown || !isString(val.type)) {
        throw new CompilerError(statement.location, "a mixin statement must be a string known at compile time.");
    }

    auto tstream = lex(val.knownString, val.location);
    tstream.get();  // Skip BEGIN
    
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
    auto parent = mod.currentFunction.cfgTail;
    auto ifblock = new BasicBlock("if");
    auto ifout = new BasicBlock("else");
    parent.children ~= ifblock;
    
    mod.pushScope();
    LLVMBasicBlockRef ifBB, elseBB;
    genIfCondition(statement.ifCondition, mod, ifBB, elseBB);
    auto endifBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "endif");
    LLVMPositionBuilderAtEnd(mod.builder, ifBB);
    mod.currentFunction.currentBasicBlock = ifBB;
    
    mod.currentFunction.cfgTail = ifblock;
    genStatement(statement.thenStatement, mod);
    
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
        genStatement(statement.elseStatement, mod);
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

void genIfCondition(ast.IfCondition condition, Module mod, out LLVMBasicBlockRef ifBB, out LLVMBasicBlockRef elseBB)
{ 
    auto expr = genExpression(condition.expression, mod);
    expr = implicitCast(condition.expression.location, expr, new BoolType(mod));
    
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


void genWhileStatement(ast.WhileStatement statement, Module mod)
{
    auto loop = Loop(mod, "while");
    
    void genTop()
    {
        auto expr = genExpression(statement.expression, mod);
        expr = implicitCast(statement.expression.location, expr, new BoolType(mod));
        LLVMBuildCondBr(mod.builder, expr.get(), loop.bodyBB, loop.endBB);
    }
    
    void genBody()
    {
        genStatement(statement.statement, mod);
    }
    
    void genIncrement() {}
    
    mod.pushScope();
    loop.gen(&genTop, &genBody, &genIncrement);
    mod.popScope();
}

void genDoStatement(ast.DoStatement statement, Module mod)
{
    auto loop = Loop(mod, "do", LoopStart.Body);
    
    void genBody()
    {
        genStatement(statement.statement, mod);
    }
    
    void genTop()
    {
        auto expr = genExpression(statement.expression, mod);
        expr = implicitCast(statement.expression.location, expr, new BoolType(mod));
        LLVMBuildCondBr(mod.builder, expr.get(), loop.bodyBB, loop.endBB);
    }
    
    void genIncrement() {}
    
    mod.pushScope();
    loop.gen(&genTop, &genBody, &genIncrement);
    mod.popScope();
}

void genForStatement(ast.ForStatement statement, Module mod)
{
    mod.pushScope();
    if (statement.initialise !is null) {
        genStatement(statement.initialise, mod);
    }
    
    auto loop = Loop(mod, "for");
    
    void genTop()
    {
        if (statement.test !is null) {
            auto expr = genExpression(statement.test, mod);
            expr = implicitCast(statement.test.location, expr, new BoolType(mod));
            LLVMBuildCondBr(mod.builder, expr.get(), loop.bodyBB, loop.endBB);
        } else {
            LLVMBuildBr(mod.builder, loop.bodyBB);
        }
    }
    
    void genBody()
    {   
        genStatement(statement.statement, mod);
    }
    
    void genIncrement()
    {
        if (statement.increment !is null) {
            genExpression(statement.increment, mod);
        }
    }
    
    loop.gen(&genTop, &genBody, &genIncrement);
    mod.popScope();
}

// TODO: range interface and opApply.
void genForeachStatement(ast.ForeachStatement statement, Module mod)
{
    assert(statement.form == ast.ForeachForm.Aggregate);
    
    auto aggregate = genExpression(statement.expression, mod);
    if (aggregate.type.dtype != DType.Array) {
        throw new CompilerError(statement.expression.location, format("aggregate must be of array type, not '%s'.", aggregate.type.name()));
    }
    
    ast.ForeachType index = null;
    ast.ForeachType iterator;
    if (statement.foreachTypes.length == 2) {
        index = statement.foreachTypes[0];
        iterator = statement.foreachTypes[1];
    } else if (statement.foreachTypes.length == 1) {
        iterator = statement.foreachTypes[0];
    } else {
        auto invalidArea = statement.foreachTypes[$-1].location - statement.foreachTypes[2].location;
        throw new CompilerError(invalidArea, "foreach over array cannot have more than two foreach variables.");
    }
    
    Type indexType = index && index.type == ast.ForeachTypeType.Explicit?
        astTypeToBackendType(index.explicitType, mod, OnFailure.DieWithError) : getSizeT(mod);
        
    auto indexValue = indexType.getValue(mod, index? index.location : statement.expression.location);
    indexValue.initialise(indexValue.location, indexValue.getInit(indexValue.location));
    indexValue.lvalue = true;
    
    Type iteratorType;
    if (iterator.type == ast.ForeachTypeType.Explicit) {
        iteratorType = astTypeToBackendType(iterator.explicitType, mod, OnFailure.DieWithError);
        if (iterator.isRef && iteratorType.dtype != aggregate.type.getBase().dtype) { // TODO: full comparison
            throw new CompilerError(iterator.explicitType.location, format("ref iterator over type '%s' must be of exact type '%s'.", aggregate.type.name(), aggregate.type.getBase().name()));
        }
    } else {
        iteratorType = aggregate.type.getBase();
    }
    
    auto aggregateLength = aggregate.getMember(statement.expression.location, "length");
    
    auto loop = Loop(mod, "foreach");
    
    void genTop()
    {
        if (index !is null) {
            Value exposedIndex;
            if (index.isRef) {
                exposedIndex = indexValue;
            } else {
                exposedIndex = indexType.getValue(mod, index.location);
                exposedIndex.initialise(index.location, indexValue);
                exposedIndex.lvalue = true;
            }
            mod.currentScope.add(extractIdentifier(index.identifier), new Store(exposedIndex));
        }
        
        auto expr = indexValue.lt(indexValue.location, aggregateLength);
        LLVMBuildCondBr(mod.builder, expr.get(), loop.bodyBB, loop.endBB);
    }
    
    void genBody()
    {
        auto iteratorValue = aggregate.index(statement.expression.location, indexValue);
        
        Value exposedIterator;
        if (iterator.isRef) {
            exposedIterator = iteratorValue;
        } else {
            exposedIterator = iteratorType.getValue(mod, iterator.location);
            exposedIterator.initialise(iterator.location, implicitCast(iteratorValue.location, iteratorValue, iteratorType));
        }
        exposedIterator.lvalue = true;
        mod.currentScope.add(extractIdentifier(iterator.identifier), new Store(exposedIterator));
        
        genStatement(statement.statement, mod);
    }
    
    void genIncrement()
    {
        indexValue.set(indexValue.location, indexValue.inc(indexValue.location));
    }
    
    mod.pushScope();
    loop.gen(&genTop, &genBody, &genIncrement);
    mod.popScope();
}

void genForeachRangeStatement(ast.ForeachStatement statement, Module mod)
{
    assert(statement.form == ast.ForeachForm.Range);
    
    auto from = genExpression(statement.expression, mod);
    auto to = genExpression(statement.rangeEnd, mod);
    
    auto iterator = statement.foreachTypes[0];
    
    Type iteratorType;
    if (iterator.type == ast.ForeachTypeType.Explicit) {
        iteratorType = astTypeToBackendType(iterator.explicitType, mod, OnFailure.DieWithError);
    } else {
        iteratorType = from.type; // HACK: this should be the equivalent of true? from : to
    }
    
    from = implicitCast(from.location, from, iteratorType);
    to = implicitCast(to.location, to, iteratorType);
    
    Value iteratorValue = iteratorType.getValue(mod, iterator.location);
    iteratorValue.initialise(iterator.location, from);
    iteratorValue.lvalue = true;
    
    auto loop = Loop(mod, "foreach");
    
    void genTop()
    {
        Value exposedIterator;
        if (iterator.isRef) {
            exposedIterator = iteratorValue;
        } else {
            exposedIterator = iteratorType.getValue(mod, iterator.location);
            exposedIterator.initialise(iterator.location, iteratorValue);
            exposedIterator.lvalue = true;
        }
        mod.currentScope.add(extractIdentifier(iterator.identifier), new Store(exposedIterator));
        
        auto expr = iteratorValue.lt(iteratorValue.location, to);
        LLVMBuildCondBr(mod.builder, expr.get(), loop.bodyBB, loop.endBB);
    }
    
    void genBody()
    {
        genStatement(statement.statement, mod);
    }
    
    void genIncrement()
    {
        iteratorValue.set(iteratorValue.location, iteratorValue.inc(iteratorValue.location));
    }
    
    mod.pushScope();
    loop.gen(&genTop, &genBody, &genIncrement);
    mod.popScope();
}

void genBreakStatement(ast.BreakStatement statement, Module mod)
{
    if (statement.target !is null) {
        throw new CompilerPanic(statement.location, "targeted break is unimplemented.");
    }
    
    if (auto loop = mod.topLoop) {
        loop.genBreak();
        declareExitBlock("break", mod);
    } else {
        throw new CompilerError(statement.location, "break statement must be in a loop or switch statement.");
    }
}

void genContinueStatement(ast.ContinueStatement statement, Module mod)
{
    if (statement.target !is null) {
        throw new CompilerPanic(statement.location, "targeted continue is unimplemented.");
    }
    
    if (auto loop = mod.topLoop) {
        loop.genContinue();
        declareExitBlock("continue", mod);
    } else {
        throw new CompilerError(statement.location, "continue statement must be in a loop.");
    }
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
    auto t = mod.currentFunction.type.returnType;
    if (t.dtype == DType.Void) {
        LLVMBuildRetVoid(mod.builder);
    } else {
        auto retval = genExpression(statement.retval, mod);
        retval = implicitCast(retval.location, retval, t);
        LLVMBuildRet(mod.builder, retval.get());
    }
    
    declareExitBlock("return", mod);
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
    auto exception = genExpression(statement.exception, mod);
    if (exception.type.dtype != DType.Class) {
        throw new CompilerError(exception.location, "can only throw class instances.");
    }
    LLVMBuildUnwind(mod.builder);
    
    declareExitBlock("throw", mod);
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
