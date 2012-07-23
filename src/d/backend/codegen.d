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
		auto type = new TypeGen();
		type.visit(var.type);
		auto alloca = LLVMBuildAlloca(builder, type.type, "");
		
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
	
	void visit(IfStatement ifs) {
		auto expression = new ExpressionGen(builder, declarationGen);
		expression.visit(ifs.condition);
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto thenBB = LLVMAppendBasicBlock(fun, "then");
		auto elseBB = LLVMAppendBasicBlock(fun, "else");
		auto mergeBB = LLVMAppendBasicBlock(fun, "merge");
		
		LLVMBuildCondBr(builder, expression.value, thenBB, elseBB);
		
		// Emit then value
		LLVMPositionBuilderAtEnd(builder, thenBB);
		
		this.visit(ifs.then);
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of else can change the current block, so we put everything in order.
		thenBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(elseBB, thenBB);
		LLVMPositionBuilderAtEnd(builder, elseBB);
		
		// TODO: Codegen for else.
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of else can change the current block, so we put everything in order.
		elseBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, elseBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
		
		// TODO: generate phi to merge everything back.
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
	
	private void handleIntegerLiteral(bool signed)(IntegerLiteral!signed il) {
		auto type = new TypeGen();
		type.visit(il.type);
		
		value = LLVMConstInt(type.type, il.value, signed);
	}
	
	void visit(IntegerLiteral!true il) {
		handleIntegerLiteral!true(il);
	}
	
	void visit(IntegerLiteral!false il) {
		handleIntegerLiteral!false(il);
	}
	
	private void handleBinaryOp(alias LLVMBuildOp, BinaryExpression)(BinaryExpression e) {
		visit(e.lhs);
		auto lhs = value;
		
		visit(e.rhs);
		
		value = LLVMBuildOp(builder, lhs, value, "");
	}
	
	void visit(AddExpression add) {
		handleBinaryOp!LLVMBuildAdd(add);
	}
	
	void visit(SubExpression sub) {
		handleBinaryOp!LLVMBuildSub(sub);
	}
	
	void visit(MulExpression mul) {
		handleBinaryOp!LLVMBuildMul(mul);
	}
	
	void visit(DivExpression div) {
		// Check signed/unsigned.
		handleBinaryOp!LLVMBuildSDiv(div);
	}
	
	void visit(ModExpression mod) {
		// Check signed/unsigned.
		handleBinaryOp!LLVMBuildSRem(mod);
	}
	
	void visit(IdentifierExpression e) {
		//*
		value = declarationGen.variables[e.identifier.name];
		/*/
		value = LLVMBuildLoad(builder, declarationGen.variables[e.identifier.name], "");
		//*/
	}
	
	void handleComparaison(LLVMIntPredicate predicate, BinaryExpression)(BinaryExpression e) {
		handleBinaryOp!(function(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, const char* name) {
			return LLVMBuildICmp(builder, predicate, lhs, rhs, name);
		})(e);
	}
	
	// TODO: handled signed and unsigned !
	void visit(LessExpression e) {
		handleComparaison!(LLVMIntPredicate.ULT)(e);
	}
	
	void visit(LessEqualExpression e) {
		handleComparaison!(LLVMIntPredicate.ULE)(e);
	}
	
	void visit(GreaterExpression e) {
		handleComparaison!(LLVMIntPredicate.UGT)(e);
	}
	
	void visit(GreaterEqualExpression e) {
		handleComparaison!(LLVMIntPredicate.UGE)(e);
	}
}

import d.ast.type;

class TypeGen {
	LLVMTypeRef type;
	
	void visit(Type t) {
		this.dispatch(t);
	}
	
	void visit(BuiltinType!int) {
		type = LLVMInt32Type();
	}
	
	void visit(BuiltinType!uint) {
		type = LLVMInt32Type();
	}
	
	void visit(BuiltinType!long) {
		type = LLVMInt64Type();
	}
	
	void visit(BuiltinType!ulong) {
		type = LLVMInt64Type();
	}
}

