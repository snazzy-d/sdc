module d.llvm.symbol;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

final class SymbolGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMValueRef[ValueSymbol] valueSymbols;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void visit(Symbol s) {
		if(auto v = cast(ValueSymbol) s) {
			visit(v);
		} else if(auto t = cast(TypeSymbol) s) {
			visit(t);
		}
	}
	
	LLVMValueRef visit(ValueSymbol s) {
		return valueSymbols.get(s, this.dispatch(s));
	}
	
	LLVMValueRef visit(Function f) {
		auto type = pass.visit(f.type);
		
		auto funType = LLVMGetElementType(type);
		auto fun = LLVMAddFunction(dmodule, f.mangle.toStringz(), funType);
		
		// Register the function.
		valueSymbols[f] = fun;
		
		if(f.fbody) {
			genFunctionBody(f, fun);
		}
		
		return fun;
	}
	
	LLVMValueRef visit(Method m) {
		return visit(cast(Function) m);
	}
	
	private void genFunctionBody(Function f) {
		genFunctionBody(f, valueSymbols[f]);
	}
	
	private void genFunctionBody(Function f, LLVMValueRef fun) {
		// Function can be defined in several modules, so the optimizer can do its work.
		LLVMSetLinkage(fun, LLVMLinkage.WeakODR);
		
		// Alloca and instruction block.
		auto allocaBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "");
		auto bodyBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "body");
		
		// Ensure we are rentrant.
		auto backupCurrentBB = LLVMGetInsertBlock(builder);
		auto oldThisPtr = thisPtr;
		auto oldLpContext = lpContext;
		auto oldCatchClauses = catchClauses;
		auto oldUnwindBlocks = unwindBlocks;
		auto oldBreakUnwindBlock = breakUnwindBlock;
		auto oldContinueUnwindBlock = continueUnwindBlock;
		
		scope(exit) {
			if(backupCurrentBB) {
				LLVMPositionBuilderAtEnd(builder, backupCurrentBB);
			} else {
				LLVMClearInsertionPosition(builder);
			}
			
			thisPtr = oldThisPtr;
			lpContext = oldLpContext;
			catchClauses = oldCatchClauses;
			unwindBlocks = oldUnwindBlocks;
			breakUnwindBlock = oldBreakUnwindBlock;
			continueUnwindBlock = oldContinueUnwindBlock;
		}
		
		// XXX: what is the way to flush an AA ?
		lpContext = null;
		catchClauses = [];
		unwindBlocks = [];
		
		// Handle parameters in the alloca block.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		
		auto funType = LLVMGetElementType(LLVMTypeOf(fun));
		
		LLVMValueRef[] params;
		LLVMTypeRef[] paramTypes;
		params.length = paramTypes.length = LLVMCountParamTypes(funType);
		LLVMGetParams(fun, params.ptr);
		LLVMGetParamTypes(funType, paramTypes.ptr);
		
		auto parameters = f.params;
		
		thisPtr = null;
		if(f.hasThis) {
			auto thisType = (cast(FunctionType) f.type.type).paramTypes[0];
			auto value = params[0];
			
			if(thisType.isRef || thisType.isFinal) {
				LLVMSetValueName(value, "this");
				thisPtr = LLVMGetFirstParam(fun);
			} else {
				auto alloca = LLVMBuildAlloca(builder, paramTypes[0], "this");
				LLVMSetValueName(value, "arg.this");
				
				LLVMBuildStore(builder, value, alloca);
				thisPtr = alloca;
			}
			
			params = params[1 .. $];
			paramTypes = paramTypes[1 .. $];
		}
		
		foreach(i, p; parameters) {
			auto type = p.pt;
			auto value = params[i];
			
			if(type.isRef || type.isFinal) {
				LLVMSetValueName(value, p.mangle.toStringz());
				valueSymbols[p] = value;
			} else {
				auto name = p.name.toString(context);
				auto alloca = LLVMBuildAlloca(builder, paramTypes[i], name.toStringz());
				LLVMSetValueName(value, ("arg." ~ name).toStringz());
				
				LLVMBuildStore(builder, value, alloca);
				valueSymbols[p] = alloca;
			}
		}
		
		// Generate function's body.
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		import d.llvm.statement;
		auto sg = StatementGen(pass);
		sg.visit(f.fbody);
		
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
	}
	
	LLVMValueRef visit(Variable var) {
		auto value = pass.visit(var.value);
		
		import d.ast.base;
		if(var.storage == Storage.Enum) {
			return valueSymbols[var] = value;
		}
		
		if(var.storage == Storage.Static) {
			auto globalVar = LLVMAddGlobal(dmodule, pass.visit(var.type), var.mangle.toStringz());
			LLVMSetThreadLocal(globalVar, true);
			
			// Register the variable.
			valueSymbols[var] = globalVar;
			
			// Store the initial value into the global variable.
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
			valueSymbols[var] = alloca;
			
			// Store the initial value into the alloca.
			LLVMBuildStore(builder, value, alloca);
			
			import d.context;
			if(var.name == BuiltinName!"this") {
				thisPtr = alloca;
			}
			
			return alloca;
		}
	}
	
	LLVMTypeRef visit(TypeSymbol s) {
		return this.dispatch(s);
	}
	
	LLVMTypeRef visit(TypeAlias a) {
		return pass.visit(a.type);
	}
	
	LLVMTypeRef visit(Struct s) {
		auto ret = pass.visit(new StructType(s));
		
		foreach(member; s.members) {
			if(typeid(member) !is typeid(Field)) {
				visit(member);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Class c) {
		auto ret = pass.buildClassType(c);
		
		foreach(member; c.members) {
			if (auto m = cast(Method) member) {
				genFunctionBody(m);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Enum e) {
		auto type = pass.visit(new EnumType(e));
		/+
		foreach(entry; e.entries) {
			visit(entry);
		}
		+/
		return type;
	}
}

