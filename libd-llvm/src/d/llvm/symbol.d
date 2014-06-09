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
	
	private LLVMValueRef[ValueSymbol] globals;
	private LLVMValueRef[ValueSymbol] locals;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void visit(Symbol s) {
		if(auto t = cast(TypeSymbol) s) {
			visit(t);
		} else if(auto v = cast(Variable) s) {
			genCached(v);
		} else if(auto f = cast(Function) s) {
			genCached(f);
		}
	}
	
	LLVMValueRef genCached(S)(S s) {
		import d.ast.base;
		final switch(s.storage) with(Storage) {
			case Enum:
			case Static:
				return globals.get(s, visit(s));
			
			case Local:
			case Capture:
				return locals.get(s, visit(s));
		}
	}
	
	void register(ValueSymbol s, LLVMValueRef v) {
		import d.ast.base;
		final switch(s.storage) with(Storage) {
			case Enum:
			case Static:
				globals[s] = v;
				return;
			
			case Local:
			case Capture:
				locals[s] = v;
				return;
		}
	}
	
	LLVMValueRef visit(Function f) {
		auto type = pass.visit(f.type);
		
		auto funType = LLVMGetElementType(type);
		auto fun = LLVMAddFunction(dmodule, f.mangle.toStringz(), funType);
		
		// Register the function.
		register(f, fun);
		
		if(f.fbody) {
			genFunctionBody(f, fun);
		}
		
		return fun;
	}
	
	private void genFunctionBody(Function f) {
		auto fun = genCached(f);
		genFunctionBody(f, fun);
	}
	
	private void genFunctionBody(Function f, LLVMValueRef fun) {
		// Function can be defined in several modules, so the optimizer can do its work.
		LLVMSetLinkage(fun, LLVMLinkage.WeakODR);
		
		// Alloca and instruction block.
		auto allocaBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "");
		auto bodyBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "body");
		
		// Ensure we are rentrant.
		auto backupCurrentBB = LLVMGetInsertBlock(builder);
		auto oldLocals = locals;
		auto oldThisPtr = thisPtr;
		auto oldContexts = contexts;
		auto oldLpContext = lpContext;
		auto oldCatchClauses = catchClauses;
		auto oldUnwindBlocks = unwindBlocks;
		
		LLVMValueRef oldContext = f.hasContext
			? contexts[$ - 1].context
			: null;
		
		scope(exit) {
			if(backupCurrentBB) {
				LLVMPositionBuilderAtEnd(builder, backupCurrentBB);
			} else {
				LLVMClearInsertionPosition(builder);
			}
			
			locals = oldLocals;
			thisPtr = oldThisPtr;
			contexts = oldContexts;
			lpContext = oldLpContext;
			catchClauses = oldCatchClauses;
			unwindBlocks = oldUnwindBlocks;
			
			if (oldContext) {
				contexts[$ - 1].context = oldContext;
			}
		}
		
		// XXX: what is the way to flush an AA ?
		locals = null;
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
			auto thisType = f.type.paramTypes[0];
			auto value = params[0];
			
			if(thisType.isRef || thisType.isFinal) {
				LLVMSetValueName(value, "this");
				thisPtr = value;
			} else {
				auto alloca = LLVMBuildAlloca(builder, paramTypes[0], "this");
				LLVMSetValueName(value, "arg.this");
				
				LLVMBuildStore(builder, value, alloca);
				thisPtr = alloca;
			}
			
			params = params[1 .. $];
			paramTypes = paramTypes[1 .. $];
		}
		
		if (oldContext) {
			auto ctxType = f.type.paramTypes[f.hasThis];
			auto value = params[f.hasThis];
			
			if(ctxType.isRef || ctxType.isFinal) {
				LLVMSetValueName(value, "__ctx");
				contexts[$ - 1].context = value;
			} else {
				auto alloca = LLVMBuildAlloca(builder, paramTypes[f.hasThis], "__ctx");
				LLVMSetValueName(value, "arg.__ctx");
				
				LLVMBuildStore(builder, value, alloca);
				contexts[$ - 1].context = alloca;
			}
			
			params = params[1 .. $];
			paramTypes = paramTypes[1 .. $];
			
			contexts ~= Closure();
		} else {
			contexts = [Closure()];
		}
		
		foreach(i, p; parameters) {
			auto type = p.type;
			auto value = params[i];
			
			if(type.isRef || type.isFinal) {
				LLVMSetValueName(value, p.mangle.toStringz());
				locals[p] = value;
			} else {
				auto name = p.name.toString(context);
				auto alloca = LLVMBuildAlloca(builder, paramTypes[i], name.toStringz());
				LLVMSetValueName(value, ("arg." ~ name).toStringz());
				
				LLVMBuildStore(builder, value, alloca);
				locals[p] = alloca;
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
		
		// If we have a context, let's make it the right size.
		if (auto context = contexts[$ - 1].context) {
			auto size = LLVMSizeOf(LLVMGetElementType(LLVMTypeOf(context)));
			
			while(LLVMGetInstructionOpcode(context) != LLVMOpcode.Call) {
				LLVMDumpValue(context);
				
				assert(LLVMGetInstructionOpcode(context) == LLVMOpcode.BitCast);
				context = LLVMGetOperand(context, 0);
			}
			
			LLVMDumpValue(context);
			
			LLVMReplaceAllUsesWith(LLVMGetOperand(context, 0), size);
		}
	}
	
	LLVMValueRef visit(Variable v) {
		import d.llvm.expression;
		auto eg = ExpressionGen(pass);
		auto value = eg.visit(v.value);
		
		import d.ast.base;
		if(v.storage == Storage.Enum) {
			return globals[v] = value;
		}
		
		auto type = pass.visit(v.type);
		if(v.storage == Storage.Static) {
			auto globalVar = LLVMAddGlobal(dmodule, type, v.mangle.toStringz());
			LLVMSetThreadLocal(globalVar, true);
			
			// Store the initial value into the global variable.
			LLVMSetInitializer(globalVar, value);
			
			// Register the variable.
			return globals[v] = globalVar;
		}
		
		// Backup current block
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
		
		// Sanity check
		scope(success) assert(LLVMGetInsertBlock(builder) is backupCurrentBlock);
		
		LLVMValueRef addr;
		if(v.storage == Storage.Capture) {
			// Try to find out if we have the variable in a closure.
			foreach_reverse(closure; contexts[0 .. $ - 1]) {
				if (auto indexPtr = v in closure.indices) {
					addr = LLVMBuildStructGEP(builder, closure.context, *indexPtr, v.mangle.toStringz());
					LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
					
					// Register the variable.
					return locals[v] = addr;
				}
			}
			
			auto closure = &contexts[$ - 1];
			if (!closure.context) {
				closure.indices[v] = 0;
				auto alloc = eg.buildCall(druntimeGen.getAllocMemory(), [LLVMConstInt(LLVMInt8TypeInContext(llvmCtx), 0, false)]);
				
				closure.context = LLVMBuildPointerCast(builder, alloc, LLVMPointerType(LLVMStructTypeInContext(llvmCtx, &type, 1, false), 0), "");
				addr = LLVMBuildStructGEP(builder, closure.context, 0, v.mangle.toStringz());
			} else {
				auto context = closure.context;
				auto contextType = LLVMGetElementType(LLVMTypeOf(context));
				
				auto index = LLVMCountStructElementTypes(contextType);
				closure.indices[v] = index;
				
				LLVMTypeRef[] types;
				types.length = index + 1;
				LLVMGetStructElementTypes(contextType, types.ptr);
				
				types[$ - 1] = type;
				contextType = LLVMStructTypeInContext(llvmCtx, types.ptr, index + 1, false);
				LLVMValueRef size = LLVMSizeOf(contextType);
				
				closure.context = LLVMBuildPointerCast(builder, context, LLVMPointerType(contextType, 0), "");
				addr = LLVMBuildStructGEP(builder, closure.context, index, v.mangle.toStringz());
			}
		} else {
			addr = LLVMBuildAlloca(builder, type, v.mangle.toStringz());
		}
		
		// Store the initial value into the alloca.
		LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		LLVMBuildStore(builder, value, addr);
		
		import d.context;
		if(v.name == BuiltinName!"this") {
			thisPtr = addr;
		}
		
		// Register the variable.
		return locals[v] = addr;
	}
	
	LLVMValueRef visit(Parameter p) {
		return locals[p];
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

