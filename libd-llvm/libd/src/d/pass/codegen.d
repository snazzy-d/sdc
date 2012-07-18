module d.pass.codegen;

import d.ast.visitor;
import d.ast.dmodule;

import llvm.c.Core;

import std.string;

auto codeGen(Module m) {
	auto builder = LLVMCreateBuilder();
	auto dmodule = LLVMModuleCreateWithName(toStringz(m.moduleDeclaration.packages.join(".") ~ "." ~ m.moduleDeclaration.name));
	
	auto cg = new DeclarationGen(dmodule, builder);
	foreach(decl; m.declarations) {
		decl.accept(cg);
	}
	
	return dmodule;
}

import d.ast.dfunction;

class DeclarationGen : DeclarationVisitor {
	private LLVMBuilderRef builder;
	private LLVMModuleRef dmodule;
	
	this(LLVMModuleRef dmodule, LLVMBuilderRef builder) {
		this.builder = builder;
		this.dmodule = dmodule;
	}
	
	void visit(FunctionDefinition f) {
		assert(f.name == "main", "Only main can be compiled !");
		
		auto funType = LLVMFunctionType(LLVMInt32Type(), null, 0, false);
		auto fun = LLVMAddFunction(dmodule, toStringz(f.name), funType);
		
		auto basicBlock = LLVMAppendBasicBlock(fun, "entry");
		LLVMPositionBuilderAtEnd(builder, basicBlock);
		
		f.fbody.accept(new StatementGen(builder));
		
		import llvm.c.Analysis;
		LLVMVerifyFunction(fun, LLVMVerifierFailureAction.PrintMessage);
	}
}

import d.ast.statement;

class StatementGen : StatementVisitor {
	private LLVMBuilderRef builder;
	
	this(LLVMBuilderRef builder){
		this.builder = builder;
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			s.accept(new StatementGen(builder));
		}
	}
	
	void visit(ReturnStatement f) {
		auto expression = new ExpressiontGen(builder);
		f.value.accept(expression);
		
		LLVMBuildRet(builder, expression.value);
	}
}

import d.ast.expression;

class ExpressiontGen : ExpressionVisitor {
	private LLVMBuilderRef builder;
	LLVMValueRef value;
	
	this(LLVMBuilderRef builder) {
		this.builder = builder;
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
	
	private final void handleBinaryOp(alias LLVMBuildOp)(BinaryExpression e) {
		e.lhs.accept(this);
		auto lhs = value;
		
		e.rhs.accept(this);
		
		value = LLVMBuildOp(builder, lhs, value, "tmp");
	}
	
	void visit(AdditionExpression add) {
		handleBinaryOp!LLVMBuildAdd(add);
	}
	
	void visit(SubstractionExpression sub) {
		handleBinaryOp!LLVMBuildSub(sub);
	}
	
	void visit(ConcatExpression concat) {
		import std.stdio;
		writeln("concat");
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
		handleBinaryOp!LLVMBuildSRem(div);
	}
	
	void visit(PowExpression pow) {
		import std.stdio;
		writeln("pow");
	}
}

