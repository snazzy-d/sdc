module d.backend.codegen;

import d.ast.dmodule;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

auto codeGen(Module[] modules) {
	auto cg = new CodeGenPass();
	
	cg.visit(modules);
	
	return cg.dmodule;
}

class CodeGenPass {
	private DeclarationGen declarationGen;
	private StatementGen statementGen;
	private ExpressionGen expressionGen;
	private AddressOfGen addressOfGen;
	private TypeGen typeGen;
	
	private LLVMBuilderRef builder;
	private LLVMModuleRef dmodule;
	
	private LLVMValueRef[ExpressionSymbol] exprSymbols;
	private LLVMTypeRef[TypeSymbol] typeSymbols;
	
	bool isSigned;
	
	this() {
		declarationGen	= new DeclarationGen(this);
		statementGen	= new StatementGen(this);
		expressionGen	= new ExpressionGen(this);
		addressOfGen	= new AddressOfGen(this);
		typeGen			= new TypeGen(this);
		
		builder = LLVMCreateBuilder();
	}
	
final:
	Module[] visit(Module[] modules) {
		dmodule = LLVMModuleCreateWithName(modules.back.location.filename.toStringz());
		
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);
		
		return modules.map!(m => visit(m)).array();
	}
	
	Module visit(Module m) {
		foreach(decl; m.declarations) {
			visit(decl);
		}
		
		return m;
	}
	
	auto visit(Declaration decl) {
		return declarationGen.visit(decl);
	}
	
	auto visit(ExpressionSymbol s) {
		return declarationGen.visit(s);
	}
	
	auto visit(TypeSymbol s) {
		return declarationGen.visit(s);
	}
	
	auto visit(Statement stmt) {
		return statementGen.visit(stmt);
	}
	
	auto visit(Expression e) {
		return expressionGen.visit(e);
	}
	
	auto visit(Type t) {
		return typeGen.visit(t);
	}
}

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;

class DeclarationGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
final:
	void visit(Declaration d) {
		if(auto es = cast(ExpressionSymbol) d) {
			visit(es);
		} else if(auto ts = cast(TypeSymbol) d) {
			visit(ts);
		}
	}
	
	LLVMValueRef visit(ExpressionSymbol s) {
		return exprSymbols.get(s, this.dispatch(s));
	}
	
	LLVMValueRef visit(FunctionDeclaration d) {
		auto funptrType = pass.visit(d.type);
		
		auto funType = LLVMGetElementType(funptrType);
		auto fun = LLVMAddFunction(dmodule, d.funmangle.toStringz(), funType);
		
		// Experimental, unify function declaration and function variables.
		auto var = LLVMAddGlobal(dmodule, funptrType, d.mangle.toStringz());
		LLVMSetInitializer(var, fun);
		LLVMSetGlobalConstant(var, true);
		
		// Register the function.
		exprSymbols[d] = var;
		
		return var;
	}
	
	LLVMValueRef visit(FunctionDefinition f) {
		// Ensure we are rentrant.
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		scope(exit) LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		
		auto funptrType = pass.visit(f.type);
		
		auto funType = LLVMGetElementType(funptrType);
		auto fun = LLVMAddFunction(dmodule, f.funmangle.toStringz(), funType);
		
		// Experimental, unify function declaration and function variables.
		auto var = LLVMAddGlobal(dmodule, funptrType, f.mangle.toStringz());
		LLVMSetInitializer(var, fun);
		LLVMSetGlobalConstant(var, true);
		
		// Register the function.
		exprSymbols[f] = var;
		
		// Alloca and instruction block.
		auto allocaBB = LLVMAppendBasicBlock(fun, "");
		auto bodyBB = LLVMAppendBasicBlock(fun, "body");
		
		// Handle parameters in the alloca block.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		
		LLVMValueRef[] params;
		LLVMTypeRef[] parameterTypes;
		params.length = parameterTypes.length = f.parameters.length;
		LLVMGetParams(fun, params.ptr);
		LLVMGetParamTypes(funType, parameterTypes.ptr);
		
		foreach(i, p; f.parameters) {
			auto value = params[i];
			
			if(p.isReference) {
				LLVMSetValueName(value, p.name.toStringz());
				
				exprSymbols[p] = value;
			} else {
				auto alloca = LLVMBuildAlloca(builder, parameterTypes[i], p.name.toStringz());
				
				LLVMSetValueName(value, ("arg." ~ p.name).toStringz());
				
				LLVMBuildStore(builder, value, alloca);
				exprSymbols[p] = alloca;
			}
		}
		
		// Generate function's body.
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		pass.visit(f.fbody);
		
		// If the current block isn't concluded, it means that it is unreachable.
		if(!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			// FIXME: provide the right AST in case of void function.
			if(LLVMGetTypeKind(LLVMGetReturnType(funType)) == LLVMTypeKind.Void) {
				LLVMBuildRetVoid(builder);
			} else {
				LLVMBuildUnreachable(builder);
			}
		}
		
		// Branch from alloca block to function body.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		LLVMBuildBr(builder, bodyBB);
		
		LLVMVerifyFunction(fun, LLVMVerifierFailureAction.PrintMessage);
		
		return var;
	}
	
	LLVMValueRef visit(VariableDeclaration var) {
		if(var.isStatic) {
			auto globalVar = LLVMAddGlobal(dmodule, pass.visit(var.type), var.mangle.toStringz());
			// FIXME: interpreter don't support TLS for now.
			// LLVMSetThreadLocal(globalVar, true);
			
			// Register the variable.
			exprSymbols[var] = globalVar;
			
			// Store the initial value into the alloca.
			auto value = pass.visit(var.value);
			LLVMSetInitializer(globalVar, value);
			
			return globalVar;
		} else {
			// Backup current block
			auto backupCurrentBlock = LLVMGetInsertBlock(builder);
			LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
			
			// Create an alloca for this variable.
			auto type = pass.visit(var.type);
			auto alloca = LLVMBuildAlloca(builder, type, var.mangle.toStringz());
			
			LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
			
			// Register the variable.
			exprSymbols[var] = alloca;
			
			// Store the initial value into the alloca.
			auto value = pass.visit(var.value);
			
			LLVMBuildStore(builder, value, alloca);
			
			return alloca;
		}
	}
	
	LLVMTypeRef visit(TypeSymbol s) {
		return typeSymbols.get(s, this.dispatch(s));
	}
	
	LLVMTypeRef visit(StructDefinition sd) {
		auto llvmStruct = LLVMStructCreateNamed(LLVMGetGlobalContext(), cast(char*) sd.mangle.toStringz());
		typeSymbols[sd] = llvmStruct;
		
		LLVMTypeRef[] members;
		
		foreach(member; sd.members) {
			if(auto f = cast(FieldDeclaration) member) {
				members ~= pass.visit(f.type);
			}
		}
		
		LLVMStructSetBody(llvmStruct, members.ptr, cast(uint) members.length, false);
		
		return llvmStruct;
	}
	
	LLVMTypeRef visit(AliasDeclaration a) {
		auto llvmType = pass.visit(a.type);
		typeSymbols[a] = llvmType;
		
		return llvmType;
	}
}

import d.ast.statement;

class StatementGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
		
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(DeclarationStatement d) {
		pass.visit(d.declaration);
	}
	
	void visit(ExpressionStatement e) {
		pass.visit(e.expression);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfElseStatement ifs) {
		auto condition = pass.visit(ifs.condition);
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto thenBB = LLVMAppendBasicBlock(fun, "then");
		auto elseBB = LLVMAppendBasicBlock(fun, "else");
		auto mergeBB = LLVMAppendBasicBlock(fun, "merge");
		
		LLVMBuildCondBr(builder, condition, thenBB, elseBB);
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, thenBB);
		
		visit(ifs.then);
		
		// Codegen of then can change the current block, so we put everything in order.
		thenBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(thenBB)) {
			LLVMBuildBr(builder, mergeBB);
		}
		
		// Put the else block after the generated stuff.
		LLVMMoveBasicBlockAfter(elseBB, thenBB);
		LLVMPositionBuilderAtEnd(builder, elseBB);
		
		// Emit else
		visit(ifs.elseStatement);
		
		// Codegen of else can change the current block, so we put everything in order.
		elseBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(elseBB)) {
			LLVMBuildBr(builder, mergeBB);
		}
		
		LLVMMoveBasicBlockAfter(mergeBB, elseBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
	}
	
	private void handleLoop(LoopStatement)(LoopStatement l) {
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		enum isFor = is(LoopStatement : ForStatement);
		enum isDoWhile = is(LoopStatement : DoWhileStatement);
		
		static if(isFor) {
			auto testBB = LLVMAppendBasicBlock(fun, "for");
			auto continueBB = LLVMAppendBasicBlock(fun, "increment");
		} else {
			auto testBB = LLVMAppendBasicBlock(fun, "while");
			alias testBB continueBB;
		}
		
		auto doBB = LLVMAppendBasicBlock(fun, "do");
		auto doneBB = LLVMAppendBasicBlock(fun, "done");
		
		static if(isDoWhile) {
			alias doBB startBB;
		} else {
			alias testBB startBB;
		}
		
		// Generate initialization if appropriate
		static if(isFor) {
			visit(l.initialize);
		}
		
		// Jump into the loop.
		LLVMBuildBr(builder, startBB);
		LLVMPositionBuilderAtEnd(builder, testBB);
		
		// Test and do or jump to done.
		auto condition = pass.visit(l.condition);
		LLVMBuildCondBr(builder, condition, doBB, doneBB);
		
		// Build continue block or alias it to the test.
		static if(isFor) {
			LLVMPositionBuilderAtEnd(builder, continueBB);
			pass.visit(l.increment);
			
			LLVMBuildBr(builder, testBB);
		}
		
		// Emit do
		LLVMPositionBuilderAtEnd(builder, doBB);
		
		visit(l.statement);
		
		// Codegen of then can change the current block, so we put everything in order.
		doBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(doBB)) {
			LLVMBuildBr(builder, continueBB);
		}
		
		LLVMMoveBasicBlockAfter(doneBB, doBB);
		LLVMPositionBuilderAtEnd(builder, doneBB);
	}
	
	void visit(WhileStatement w) {
		handleLoop(w);
	}
	
	void visit(DoWhileStatement w) {
		handleLoop(w);
	}
	
	void visit(ForStatement f) {
		handleLoop(f);
	}
	
	void visit(ReturnStatement r) {
		LLVMBuildRet(builder, pass.visit(r.value));
	}
}

import d.ast.expression;

class ExpressionGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
		
final:
	LLVMValueRef visit(Expression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			auto msg = typeid(e).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(e.location, msg);
			
			assert(0, msg);
		})(e);
	}
	
	LLVMValueRef visit(BooleanLiteral bl) {
		return LLVMConstInt(pass.visit(bl.type), bl.value, false);
	}
	
	LLVMValueRef visit(IntegerLiteral!true il) {
		return LLVMConstInt(pass.visit(il.type), il.value, true);
	}
	
	LLVMValueRef visit(IntegerLiteral!false il) {
		return LLVMConstInt(pass.visit(il.type), il.value, false);
	}
	
	LLVMValueRef visit(FloatLiteral fl) {
		return LLVMConstReal(pass.visit(fl.type), fl.value);
	}
	
	// XXX: character types in backend ?
	LLVMValueRef visit(CharacterLiteral cl) {
		return LLVMConstInt(pass.visit(cl.type), cl.value[0], false);
	}
	
	LLVMValueRef visit(NullLiteral nl) {
		return LLVMConstNull(pass.visit(nl.type));
	}
	
	LLVMValueRef visit(StringLiteral sl) {
		auto fields = [LLVMConstInt(LLVMInt64Type(), sl.value.length, false), LLVMBuildGlobalStringPtr(builder, sl.value.toStringz(), ".str")];
		
		return LLVMConstStruct(fields.ptr, 2, false);
	}
	
	LLVMValueRef visit(CommaExpression ce) {
		visit(ce.lhs);
		
		return visit(ce.rhs);
	}
	
	LLVMValueRef visit(ThisExpression e) {
		return LLVMBuildLoad(builder, addressOfGen.visit(e), "");
	}
	
	LLVMValueRef visit(AssignExpression e) {
		auto ptr = addressOfGen.visit(e.lhs);
		auto value = visit(e.rhs);
		
		LLVMBuildStore(builder, value, ptr);
		
		return value;
	}
	
	LLVMValueRef visit(AddressOfExpression e) {
		return addressOfGen.visit(e.expression);
	}
	
	LLVMValueRef visit(DereferenceExpression e) {
		return LLVMBuildLoad(builder, visit(e.expression), "");
	}
	
	private auto handleIncrement(bool pre, IncrementExpression)(IncrementExpression e, int step) {
		auto ptr = addressOfGen.visit(e.expression);
		
		auto preValue = LLVMBuildLoad(builder, ptr, "");
		auto type = e.expression.type;
		
		LLVMValueRef postValue;
		
		if(auto ptrType = cast(PointerType) type) {
			auto indice = LLVMConstInt(LLVMInt64Type(), step, true);
			postValue = LLVMBuildInBoundsGEP(builder, preValue, &indice, 1, "");
		} else {
			postValue = LLVMBuildAdd(builder, preValue, LLVMConstInt(pass.visit(type), step, true), "");
		}
		
		LLVMBuildStore(builder, postValue, ptr);
		
		// PreIncrement return the value after it is incremented.
		static if(pre) {
			return postValue;
		} else {
			return preValue;
		}
	}
	
	LLVMValueRef visit(PreIncrementExpression e) {
		return handleIncrement!true(e, 1);
	}
	
	LLVMValueRef visit(PreDecrementExpression e) {
		return handleIncrement!true(e, -1);
	}
	
	LLVMValueRef visit(PostIncrementExpression e) {
		return handleIncrement!false(e, 1);
	}
	
	LLVMValueRef visit(PostDecrementExpression e) {
		return handleIncrement!false(e, -1);
	}
	
	LLVMValueRef visit(UnaryMinusExpression e) {
		return LLVMBuildSub(builder, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expression), "");
	}
	
	LLVMValueRef visit(NotExpression e) {
		// Is it the right way ?
		return LLVMBuildICmp(builder, LLVMIntPredicate.EQ, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expression), "");
	}
	
	private auto handleBinaryOp(alias LLVMBuildOp, BinaryExpression)(BinaryExpression e) {
		// XXX: should be useless, but order of evaluation of parameters is bugguy.
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		
		return LLVMBuildOp(builder, lhs, rhs, "");
	}
	
	private auto handleBinaryOp(alias LLVMSignedBuildOp, alias LLVMUnsignedBuildOp, BinaryExpression)(BinaryExpression e) {
		pass.visit(e.type);
		
		if(isSigned) {
			return handleBinaryOp!LLVMSignedBuildOp(e);
		} else {
			return handleBinaryOp!LLVMUnsignedBuildOp(e);
		}
	}
	
	LLVMValueRef visit(AddExpression add) {
		return handleBinaryOp!LLVMBuildAdd(add);
	}
	
	LLVMValueRef visit(SubExpression sub) {
		return handleBinaryOp!LLVMBuildSub(sub);
	}
	
	LLVMValueRef visit(MulExpression mul) {
		return handleBinaryOp!LLVMBuildMul(mul);
	}
	
	LLVMValueRef visit(DivExpression div) {
		return handleBinaryOp!(LLVMBuildSDiv, LLVMBuildUDiv)(div);
	}
	
	LLVMValueRef visit(ModExpression mod) {
		return handleBinaryOp!(LLVMBuildSRem, LLVMBuildURem)(mod);
	}
	
	private auto handleLogicalBinary(string operation)(BinaryExpression!operation e) if(operation == "&&" || operation == "||") {
		auto lhs = visit(e.lhs);
		
		auto lhsBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(lhsBB);
		
		static if(operation == "&&") {
			auto rhsBB = LLVMAppendBasicBlock(fun, "and_short_circuit");
			auto mergeBB = LLVMAppendBasicBlock(fun, "and_merge");
			LLVMBuildCondBr(builder, lhs, rhsBB, mergeBB);
		} else {
			auto rhsBB = LLVMAppendBasicBlock(fun, "or_short_circuit");
			auto mergeBB = LLVMAppendBasicBlock(fun, "or_merge");
			LLVMBuildCondBr(builder, lhs, mergeBB, rhsBB);
		}
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, rhsBB);
		
		auto rhs = visit(e.rhs);
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of then can change the current block, so we put everything in order.
		rhsBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, rhsBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
		
		//Generate phi to get the result.
		auto phiNode = LLVMBuildPhi(builder, pass.visit(e.type), "");
		
		LLVMValueRef[2] incomingValues;
		incomingValues[0] = lhs;
		incomingValues[1] = rhs;
		
		LLVMBasicBlockRef[2] incomingBlocks;
		incomingBlocks[0] = lhsBB;
		incomingBlocks[1] = rhsBB;
		
		LLVMAddIncoming(phiNode, incomingValues.ptr, incomingBlocks.ptr, incomingValues.length);
		
		return phiNode;
	}
	
	LLVMValueRef visit(LogicalAndExpression e) {
		return handleLogicalBinary(e);
	}
	
	LLVMValueRef visit(LogicalOrExpression e) {
		return handleLogicalBinary(e);
	}
	
	LLVMValueRef visit(SymbolExpression e) {
		return LLVMBuildLoad(builder, addressOfGen.visit(e), "");
	}
	
	LLVMValueRef visit(FieldExpression e) {
		// FIXME: handle rvalues with LLVMBuildExtractValue.
		try {
			return LLVMBuildLoad(builder, addressOfGen.visit(e), "");
		} catch(Exception exp) {
			import std.stdio;
			writeln("FieldExpression isn't an lvalue.");
			
			return LLVMBuildExtractValue(builder, visit(e.expression), e.field.index, "");
		}
	}
	
	LLVMValueRef visit(IndexExpression e) {
		return LLVMBuildLoad(builder, addressOfGen.visit(e), "");
	}
	
	private auto handleComparaison(LLVMIntPredicate predicate, BinaryExpression)(BinaryExpression e) {
		return handleBinaryOp!(function(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, const char* name) {
			return LLVMBuildICmp(builder, predicate, lhs, rhs, name);
		})(e);
	}
	
	private auto handleComparaison(LLVMIntPredicate signedPredicate, LLVMIntPredicate unsignedPredicate, BinaryExpression)(BinaryExpression e) {
		// TODO: implement type comparaison.
		// assert(e.lhs.type == e.rhs.type);
		
		pass.visit(e.lhs.type);
		
		if(isSigned) {
			return handleComparaison!signedPredicate(e);
		} else {
			return handleComparaison!unsignedPredicate(e);
		}
	}
	
	LLVMValueRef visit(EqualityExpression e) {
		return handleComparaison!(LLVMIntPredicate.EQ)(e);
	}
	
	LLVMValueRef visit(NotEqualityExpression e) {
		return handleComparaison!(LLVMIntPredicate.NE)(e);
	}
	
	LLVMValueRef visit(LessExpression e) {
		return handleComparaison!(LLVMIntPredicate.SLT, LLVMIntPredicate.ULT)(e);
	}
	
	LLVMValueRef visit(LessEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.SLE, LLVMIntPredicate.ULE)(e);
	}
	
	LLVMValueRef visit(GreaterExpression e) {
		return handleComparaison!(LLVMIntPredicate.SGT, LLVMIntPredicate.UGT)(e);
	}
	
	LLVMValueRef visit(GreaterEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.SGE, LLVMIntPredicate.UGE)(e);
	}
	
	LLVMValueRef visit(PadExpression e) {
		auto type = pass.visit(e.type);
		
		pass.visit(e.expression.type);
		if(isSigned) {
			return LLVMBuildSExt(builder, visit(e.expression), type, "");
		} else {
			return LLVMBuildZExt(builder, visit(e.expression), type, "");
		}
	}
	
	LLVMValueRef visit(TruncateExpression e) {
		return LLVMBuildTrunc(builder, visit(e.expression), pass.visit(e.type), "");
	}
	
	LLVMValueRef visit(BitCastExpression e) {
		return LLVMBuildBitCast(builder, visit(e.expression), pass.visit(e.type), "");
	}
	
	LLVMValueRef visit(CallExpression c) {
		auto callee = visit(c.callee);
		
		LLVMValueRef[] arguments;
		arguments.length = c.arguments.length;
		
		auto type = cast(FunctionType) c.callee.type;
		uint i;
		foreach(param; type.parameters) {
			if(param.isReference) {
				arguments[i] = addressOfGen.visit(c.arguments[i]);
			} else {
				arguments[i] = visit(c.arguments[i]);
			}
			
			i++;
		}
		
		// Handle variadic functions.
		while(i < arguments.length) {
			arguments[i] = visit(c.arguments[i]);
			i++;
		}
		
		return LLVMBuildCall(builder, callee, arguments.ptr, cast(uint) arguments.length, "");
	}
	
	LLVMValueRef visit(TupleExpression e) {
		auto fields = e.values.map!(v => visit(v)).array();
		
		// Hack around the difference between struct and named struct in LLVM.
		if(e.type) {
			auto type = pass.visit(e.type);
			return LLVMConstNamedStruct(type, fields.ptr, cast(uint) fields.length);
		}
		
		return LLVMConstStruct(fields.ptr, cast(uint) fields.length, false);
	}
	
	LLVMValueRef visit(VoidInitializer v) {
		return LLVMGetUndef(pass.visit(v.type));
	}
}

class AddressOfGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
final:
	LLVMValueRef visit(Expression e) {
		return this.dispatch(e);
	}
	
	LLVMValueRef visit(SymbolExpression e) {
		return pass.visit(e.symbol);
	}
	
	LLVMValueRef visit(FieldExpression e) {
		auto ptr = visit(e.expression);
		
		return LLVMBuildStructGEP(builder, ptr, e.field.index, "");
	}
	
	LLVMValueRef visit(ThisExpression e) {
		return LLVMGetFirstParam(LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder)));
	}
	
	LLVMValueRef visit(DereferenceExpression e) {
		return pass.visit(e.expression);
	}
	
	LLVMValueRef visit(BitCastExpression e) {
		return LLVMBuildBitCast(builder, visit(e.expression), LLVMPointerType(pass.visit(e.type), 0), "");
	}
	
	LLVMValueRef visit(IndexExpression e) {
		assert(e.parameters.length == 1);
		
		auto indexedType = e.indexed.type;
		
		auto indexed = visit(e.indexed);
		auto indice = pass.visit(e.parameters[0]);
		
		if(typeid(indexedType) is typeid(SliceType)) {
			// TODO: add bound checking.
			auto length = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, indexed, 0, ""), ".length");
			
			auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.ULT, LLVMBuildZExt(builder, indice, LLVMInt64Type(), ""), length, "");
			auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
			
			auto failBB = LLVMAppendBasicBlock(fun, "arrayBoundFail");
			auto okBB = LLVMAppendBasicBlock(fun, "arrayBoundOK");
			
			LLVMBuildCondBr(builder, condition, okBB, failBB);
			
			// Emit bound check fail code.
			LLVMPositionBuilderAtEnd(builder, failBB);
			LLVMBuildUnreachable(builder);
			
			// And continue regular program flow.
			LLVMPositionBuilderAtEnd(builder, okBB);
			
			indexed = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, indexed, 1, ""), ".ptr");
		} else if(typeid(indexedType) is typeid(StaticArrayType)) {
			auto indices = [LLVMConstInt(LLVMInt64Type(), 0, false), indice];
			
			return LLVMBuildInBoundsGEP(builder, indexed, indices.ptr, 2, "");
		}
		
		return LLVMBuildInBoundsGEP(builder, indexed, &indice, 1, "");
	}
}

import d.ast.type;

class TypeGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
final:
	LLVMTypeRef visit(Type t) {
		return this.dispatch!(function LLVMTypeRef(Type t) {
			auto msg = typeid(t).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(t.location, msg);
			
			assert(0, msg);
		})(t);
	}
	
	LLVMTypeRef visit(SymbolType t) {
		return pass.visit(t.symbol);
	}
	
	LLVMTypeRef visit(BooleanType t) {
		isSigned = false;
		
		return LLVMInt1Type();
	}
	
	LLVMTypeRef visit(IntegerType t) {
		isSigned = !(t.type % 2);
		
		final switch(t.type) {
				case Integer.Byte, Integer.Ubyte :
					return LLVMInt8Type();
				
				case Integer.Short, Integer.Ushort :
					return LLVMInt16Type();
				
				case Integer.Int, Integer.Uint :
					return LLVMInt32Type();
				
				case Integer.Long, Integer.Ulong :
					return LLVMInt64Type();
		}
	}
	
	LLVMTypeRef visit(FloatType t) {
		isSigned = true;
		
		final switch(t.type) {
				case Float.Float :
					return LLVMFloatType();
				
				case Float.Double :
					return LLVMDoubleType();
				
				case Float.Real :
					return LLVMX86FP80Type();
		}
	}
	
	// XXX: character type in the backend ?
	LLVMTypeRef visit(CharacterType t) {
		isSigned = false;
		
		final switch(t.type) {
				case Character.Char :
					return LLVMInt8Type();
				
				case Character.Wchar :
					return LLVMInt16Type();
				
				case Character.Dchar :
					return LLVMInt32Type();
		}
	}
	
	LLVMTypeRef visit(VoidType t) {
		return LLVMVoidType();
	}
	
	LLVMTypeRef visit(PointerType t) {
		auto pointed = visit(t.type);
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visit(SliceType t) {
		auto types = [LLVMInt64Type(), LLVMPointerType(visit(t.type), 0)];
		
		return LLVMStructType(types.ptr, 2, false);
	}
	
	LLVMTypeRef visit(StaticArrayType t) {
		auto type = visit(t.type);
		auto size = pass.visit(t.size);
		
		return LLVMArrayType(type, cast(uint) LLVMConstIntGetZExtValue(size));
	}
	
	LLVMTypeRef visit(FunctionType t) {
		auto parameterTypes = t.parameters.map!((p) {
			auto type = visit(p.type);
			
			if(p.isReference) {
				type = LLVMPointerType(type, 0);
			}
			
			return type;
		}).array();
		
		return LLVMPointerType(LLVMFunctionType(visit(t.returnType), parameterTypes.ptr, cast(uint) parameterTypes.length, t.isVariadic), 0);
	}
}

