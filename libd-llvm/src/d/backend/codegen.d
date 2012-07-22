module d.backend.codegen;

import d.ast.dmodule;

import util.visitor;

import llvm.c.Analysis;
import llvm.c.Core;

import std.string;

auto codeGen(Module m) {
	auto builder = LLVMCreateBuilder();
	auto dmodule = LLVMModuleCreateWithName(m.location.filename.toStringz());
	
	// Dump module content on exit (for debug purpose).
	scope(exit) LLVMDumpModule(dmodule);
	
	auto cg = new DeclarationGen(dmodule, builder);
	foreach(decl; m.declarations) {
		cg.visit(decl);
	}
	
	return dmodule;
}

import d.ast.declaration;
import d.ast.dfunction;

class DeclarationGen {
	private LLVMBuilderRef builder;
	private LLVMModuleRef dmodule;
	
	LLVMValueRef[string] variables;
	
	this(LLVMModuleRef dmodule, LLVMBuilderRef builder) {
		this.builder = builder;
		this.dmodule = dmodule;
	}
	
final:
	void visit(Declaration d) {
		this.dispatch(d);
	}
	
	void visit(FunctionDefinition f) {
		assert(f.name == "main", "Only main can be compiled !");
		
		auto funType = LLVMFunctionType(LLVMInt32Type(), null, 0, false);
		auto fun = LLVMAddFunction(dmodule, toStringz(f.name), funType);
		
		// Instruction block.
		auto basicBlock = LLVMAppendBasicBlock(fun, "");
		LLVMPositionBuilderAtEnd(builder, basicBlock);
		
		(new StatementGen(builder, this)).visit(f.fbody);
		
		LLVMVerifyFunction(fun, LLVMVerifierFailureAction.PrintMessage);
	}
	
	void visit(VariablesDeclaration decls) {
		foreach(var; decls.variables) {
			visit(var);
		}
	}
	
	void visit(VariableDeclaration var) {
		auto expression = new ExpressionGen(builder, this);
		expression.visit(var.value);
		
		// Backup current block
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
		
		// Create an alloca for this variable.
		auto alloca = LLVMBuildAlloca(builder, LLVMInt32Type(), "");
		
		LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		
		// Store the initial value into the alloca.
		LLVMBuildStore(builder, expression.value, alloca);
		
		//*
		variables[var.name] = expression.value;
		/*/
		variables[var.name] = alloca;
		//*/
	}
}

import d.ast.statement;

class StatementGen {
	private LLVMBuilderRef builder;
	private DeclarationGen declarationGen;
	
	this(LLVMBuilderRef builder, DeclarationGen declarationGen){
		this.builder = builder;
		this.declarationGen = declarationGen;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(DeclarationStatement d) {
		declarationGen.visit(d.declaration);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(ReturnStatement f) {
		auto expression = new ExpressionGen(builder, declarationGen);
		expression.visit(f.value);
		
		LLVMBuildRet(builder, expression.value);
	}
}

import d.ast.expression;

class ExpressionGen {
	private LLVMBuilderRef builder;
	private DeclarationGen declarationGen;
	
	LLVMValueRef value;
	
	this(LLVMBuilderRef builder, DeclarationGen declarationGen) {
		this.builder = builder;
		this.declarationGen = declarationGen;
	}
	
final:
	void visit(Expression e) {
		this.dispatch(e);
	}
	
	void visit(IntegerLiteral!int i32) {
		value = LLVMConstInt(LLVMInt32Type(), i32.value, true);
	}
	
	void visit(IntegerLiteral!uint i32) {
		value = LLVMConstInt(LLVMInt32Type(), i32.value, false);
	}
	
	void visit(IntegerLiteral!long i64) {
		value = LLVMConstInt(LLVMInt64Type(), i64.value, true);
	}
	
	void visit(IntegerLiteral!ulong i64) {
		value = LLVMConstInt(LLVMInt64Type(), i64.value, false);
	}
	
	private void handleBinaryOp(alias LLVMBuildOp)(BinaryExpression e) {
		visit(e.lhs);
		auto lhs = value;
		
		visit(e.rhs);
		
		value = LLVMBuildOp(builder, lhs, value, "");
	}
	
	void visit(AdditionExpression add) {
		handleBinaryOp!LLVMBuildAdd(add);
	}
	
	void visit(SubstractionExpression sub) {
		handleBinaryOp!LLVMBuildSub(sub);
	}
	
	void visit(ConcatExpression concat) {
		assert(0, "concat is not implemented.");
	}
	
	void visit(MultiplicationExpression mul) {
		handleBinaryOp!LLVMBuildMul(mul);
	}
	
	void visit(DivisionExpression div) {
		// Check signed/unsigned.
		handleBinaryOp!LLVMBuildSDiv(div);
	}
	
	void visit(ModulusExpression mod) {
		// Check signed/unsigned.
		handleBinaryOp!LLVMBuildSRem(mod);
	}
	
	void visit(PowExpression pow) {
		assert(0, "pow is not implemented.");
	}
	
	void visit(IdentifierExpression e) {
		//*
		value = declarationGen.variables[e.identifier.name];
		/*/
		value = LLVMBuildLoad(builder, declarationGen.variables[e.identifier.name], "");
		//*/
	}
}

