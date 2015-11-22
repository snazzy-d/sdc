module d.llvm.local;

import d.llvm.codegen;

import d.ir.dscope;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import llvm.c.core;

alias LocalPass = LocalGen*;

enum Mode {
	Lazy,
	Eager,
}

struct Closure {
private:
	uint[Variable] indices;
	LLVMTypeRef type;
}

struct LocalData {
private:
	Closure[][TypeSymbol] embededContexts;
}

struct LocalGen {
	CodeGen pass;
	alias pass this;
	
	LLVMBuilderRef builder;
	
	Mode mode;
	
	LLVMValueRef ctxPtr;
	
	LLVMValueRef[ValueSymbol] locals;
	
	Closure[] contexts;
	
	LLVMValueRef lpContext;
	LLVMValueRef[] catchClauses;
	
	enum BlockKind {
		Exit,
		Success,
		Failure,
		Catch,
	}
	
	struct Block {
		BlockKind kind;
		Statement statement;
		LLVMBasicBlockRef landingPadBB;
		LLVMBasicBlockRef unwindBB;
	}
	
	Block[] unwindBlocks;
	
	this(CodeGen pass, Mode mode = Mode.Lazy, Closure[] contexts = []) {
		this.pass = pass;
		this.mode = mode;
		this.contexts = contexts;
		
		// Make sure globals are initialized.
		locals[null] = null;
		locals.remove(null);
		
		// Make sure we alays have a builder ready to rock.
		builder = LLVMCreateBuilderInContext(llvmCtx);
	}
	
	~this() {
		LLVMDisposeBuilder(builder);
	}
	
	@disable this(this);
	
	void define(Symbol s) {
		if (auto v = cast(Variable) s) {
			define(v);
		} else if (auto f = cast(Function) s) {
			define(f);
		} else if (auto t = cast(TypeSymbol) s) {
			define(t);
		} else {
			import d.llvm.global;
			GlobalGen(pass, mode).define(s);
		}
	}
	
	void require(Function f) {
		if (f.step == Step.Processed) {
			return;
		}
		
		LLVMValueRef[] unreachables;
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		scope(exit) {
			foreach(u; unreachables) {
				LLVMInstructionEraseFromParent(u);
			}
			
			LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		}
		
		// OK we need to require. We need to put the module in a good state.
		for (
			auto fun = LLVMGetFirstFunction(dmodule);
			fun !is null;
			fun = LLVMGetNextFunction(fun)
		) {
			for (
				auto bb = LLVMGetFirstBasicBlock(fun);
				bb !is null;
				bb = LLVMGetNextBasicBlock(bb)
			) {
				if (!LLVMGetBasicBlockTerminator(bb)) {
					LLVMPositionBuilderAtEnd(builder, bb);
					unreachables ~= LLVMBuildUnreachable(builder);
				}
			}
		}
		
		scheduler.require(f);
	}
	
	LLVMValueRef declare(Function f) {
		require(f);
		
		auto lookup = f.storage.isLocal
			? locals
			: globals;
		
		auto fun = lookup.get(f, {
			auto name = f.mangle.toStringz(pass.context);
			
			import d.llvm.type;
			auto type = LLVMGetElementType(TypeGen(pass).visit(f.type));
			
			// The method may have been defined when visiting the type.
			if (auto funPtr = f in lookup) {
				return *funPtr;
			}
			
			// Sanity check.
			auto fun = LLVMGetNamedFunction(pass.dmodule, name);
			assert(!fun, f.mangle.toString(pass.context) ~ " is already declared.");
			
			return lookup[f] = LLVMAddFunction(pass.dmodule, name, type);
		} ());
		
		if (f.hasContext || f.inTemplate || mode == Mode.Eager) {
			if (f.fbody && maybeDefine(f, fun)) {
				LLVMSetLinkage(fun, LLVMLinkage.LinkOnceODR);
			}
		}
		
		return fun;
	}
	
	LLVMValueRef define(Function f) {
		auto fun = declare(f);
		if (!f.fbody) {
			return fun;
		}
		
		if (!maybeDefine(f, fun)) {
			auto linkage = LLVMGetLinkage(fun);
			assert(linkage == LLVMLinkage.LinkOnceODR, "function " ~ f.mangle.toString(context) ~ " already defined");
			LLVMSetLinkage(fun, LLVMLinkage.External);
		}
		
		return fun;
	}
	
	private bool maybeDefine(Function f, LLVMValueRef fun) in {
		assert(f.step == Step.Processed, "f is not processed");
	} body {
		auto countBB = LLVMCountBasicBlocks(fun);
		if (countBB) {
			return false;
		}
		
		auto contexts = f.hasContext ? this.contexts : [];
		LocalGen(pass, mode, contexts).genBody(f, fun);
		
		return true;
	}
	
	private void genBody(Function f, LLVMValueRef fun) in {
		assert(LLVMCountBasicBlocks(fun) == 0, f.mangle.toString(context) ~ " body is already defined.");
		assert(f.step == Step.Processed, "f is not processed");
		assert(f.fbody, "f must have a body");
	} body {
		// Alloca and instruction block.
		auto allocaBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "");
		
		// Handle parameters in the alloca block.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		
		auto funType = LLVMGetElementType(LLVMTypeOf(fun));
		
		LLVMValueRef[] params;
		LLVMTypeRef[] paramTypes;
		params.length = paramTypes.length = LLVMCountParamTypes(funType);
		LLVMGetParams(fun, params.ptr);
		LLVMGetParamTypes(funType, paramTypes.ptr);
		
		auto parameters = f.params;
		
		import d.llvm.type;
		auto closure = Closure(f.closure, TypeGen(pass).visit(f));
		if (f.hasContext) {
			auto parentCtxType = f.type.parameters[0];
			assert(parentCtxType.isRef || parentCtxType.isFinal);
			
			auto parentCtx = params[0];
			LLVMSetValueName(parentCtx, "__ctx");
			
			// Find the right context as parent.
			import d.llvm.type, std.algorithm, std.range;
			auto ctxTypeGen = TypeGen(pass).visit(parentCtxType.getType());
			contexts = contexts[0 .. $ - retro(contexts).countUntil!(c => c.type is ctxTypeGen)()];
			
			buildCapturedVariables(parentCtx, contexts, f.getCaptures());
			
			// Chain closures.
			ctxPtr = LLVMBuildAlloca(builder, closure.type, "");
			
			LLVMBuildStore(builder, parentCtx, LLVMBuildStructGEP(builder, ctxPtr, 0, ""));
			contexts ~= closure;
		} else {
			// Build closure for this function.
			import d.llvm.type;
			closure.type = TypeGen(pass).visit(f);
			contexts = [closure];
		}
		
		if (f.hasThis) {
			auto value = params[f.hasContext];
			
			// XXX: Is that really the way we want it ?
			import d.context.name;
			auto thisParam = parameters[0];
			assert(thisParam !is null);
			
			auto thisPtr = createVariableStorage(thisParam, value);
			if (!thisParam.isRef && !thisParam.isFinal) {
				LLVMSetValueName(value, "arg.this");
			}
			
			buildEmbededCaptures(thisPtr, thisParam.type);
		}
		
		params = params[f.hasThis + f.hasContext .. $];
		paramTypes = paramTypes[f.hasThis + f.hasContext .. $];
		parameters = parameters[f.hasThis .. $];
		
		foreach(i, p; parameters) {
			auto value = params[i];
			
			createVariableStorage(p, value);
			if (!p.isRef && !p.isFinal) {
				import std.string;
				LLVMSetValueName(value, toStringz("arg." ~ p.name.toString(context)));
			}
		}
		
		// Generate function's body.
		auto bodyBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "body");
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		import d.llvm.statement;
		StatementGen(&this).visit(f.fbody);
		
		// If the current block isn't concluded, it means that it is unreachable.
		if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			// FIXME: provide the right AST in case of void function.
			if (LLVMGetTypeKind(LLVMGetReturnType(funType)) == LLVMTypeKind.Void) {
				LLVMBuildRetVoid(builder);
			} else {
				LLVMBuildUnreachable(builder);
			}
		}
		
		// Branch from alloca block to function body.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		LLVMBuildBr(builder, bodyBB);
		
		// If we have a context, let's make it the right size.
		if (ctxPtr !is null) {
			auto ctxAlloca = ctxPtr;
			while(LLVMGetInstructionOpcode(ctxAlloca) != LLVMOpcode.Alloca) {
				assert(LLVMGetInstructionOpcode(ctxAlloca) == LLVMOpcode.BitCast);
				ctxAlloca = LLVMGetOperand(ctxAlloca, 0);
			}
			
			LLVMPositionBuilderBefore(builder, ctxAlloca);
			
			auto ctxType = contexts[$ - 1].type;
			
			import d.llvm.expression, d.llvm.runtime;
			auto alloc = ExpressionGen(&this).buildCall(RuntimeGen(pass).getAllocMemory(), [LLVMSizeOf(ctxType)]);
			LLVMAddInstrAttribute(alloc, 0, LLVMAttribute.NoAlias);
			
			LLVMReplaceAllUsesWith(ctxAlloca, LLVMBuildPointerCast(builder, alloc, LLVMPointerType(ctxType, 0), ""));
		}
	}
	
	private void buildEmbededCaptures()(LLVMValueRef thisPtr, Type t) {
		if (t.kind == TypeKind.Struct) {
			auto s = t.dstruct;
			if (!s.hasContext) {
				return;
			}
			
			buildEmbededCaptures(thisPtr, s, 0);
		} else if (t.kind == TypeKind.Class) {
			auto c = t.dclass;
			if (!c.hasContext) {
				return;
			}
			
			import d.context.name, std.algorithm, std.range;
			auto f = retro(c.members)
				.filter!(m => m.name == BuiltinName!"__ctx")
				.map!(m => cast(Field) m)
				.front;
			
			buildEmbededCaptures(thisPtr, c, f.index);
		} else {
			assert(0, typeid(t).toString() ~ " is not supported.");
		}
	}
	
	private void buildEmbededCaptures(S)(
		LLVMValueRef thisPtr,
		S s,
		uint i,
	) if (is(S : Scope)) {
		buildCapturedVariables(LLVMBuildLoad(
			builder,
			LLVMBuildStructGEP(builder, thisPtr, i, ""),
			"",
		), localData.embededContexts[s], s.getCaptures());
	}
	
	private void buildCapturedVariables(
		LLVMValueRef root,
		Closure[] contexts,
		bool[Variable] capture,
	) {
		auto closureCount = capture.length;
		
		// Try to find out if we have the variable in a closure.
		foreach_reverse(closure; contexts) {
			if (!closureCount) {
				break;
			}
			
			// Create enclosed variables.
			foreach(v; capture.byKey()) {
				if (auto indexPtr = v in closure.indices) {
					// Register the variable.
					auto var = LLVMBuildStructGEP(
						builder,
						root,
						*indexPtr,
						"",
					);
					
					if (v.isRef || v.isFinal) {
						var = LLVMBuildLoad(builder, var, "");
					}
					
					LLVMSetValueName(var, v.mangle.toStringz(context));
					locals[v] = var;
					
					assert(closureCount > 0, "closureCount is 0 or lower.");
					closureCount--;
				}
			}
			
			root = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, root, 0, ""), "");
		}
		
		assert(closureCount == 0);
	}
	
	LLVMValueRef declare(Variable v) {
		// TODO: Actually just declare here :)
		return locals.get(v, define(v));
	}
	
	LLVMValueRef define(Variable v) in {
		assert(!v.isFinal);
	} body {
		if (v.storage.isGlobal) {
			import d.llvm.global;
			return GlobalGen(pass, mode).declare(v);
		}
		
		import d.llvm.expression;
		auto value = v.isRef
			? AddressOfGen(&this).visit(v.value)
			: ExpressionGen(&this).visit(v.value);
		
		return createVariableStorage(v, value);
	}
	
	private LLVMValueRef createVariableStorage(
		Variable v,
		LLVMValueRef value,
	) in {
		assert(v.storage.isLocal, "globals not supported");
	} body {
		auto name = v.mangle.toStringz(context);
		
		if (v.isRef | v.isFinal) {
			if (v.storage == Storage.Capture) {
				auto addr = createCaptureStorage(v, "");
				LLVMBuildStore(builder, value, addr);
			}
			
			LLVMSetValueName(value, name);
			return locals[v] = value;
		}
		
		// Backup current block
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(
			LLVMGetBasicBlockParent(backupCurrentBlock),
		));
		
		// Sanity check
		scope(success) {
			assert(LLVMGetInsertBlock(builder) is backupCurrentBlock);
		}
		
		import d.llvm.type;
		LLVMValueRef addr = (v.storage == Storage.Capture)
			? createCaptureStorage(v, name)
			: LLVMBuildAlloca(builder, TypeGen(pass).visit(v.type), name);
		
		// Store the initial value into the alloca.
		LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		LLVMBuildStore(builder, value, addr);
		
		// Register the variable.
		return locals[v] = addr;
	}
	
	LLVMValueRef createCaptureStorage(Variable v, const char* name) in {
		assert(v.storage == Storage.Capture, "Expected captured");
	} body {
		auto closure = &contexts[$ - 1];
		
		// If we don't have a closure, make one.
		if (ctxPtr is null) {
			ctxPtr = LLVMBuildAlloca(builder, closure.type, "");
		}
		
		return LLVMBuildStructGEP(
			builder,
			ctxPtr,
			closure.indices[v],
			name,
		);
	}
	
	LLVMValueRef getContext(Function f) {
		import d.llvm.type;
		auto type = TypeGen(pass).visit(f);
		auto value = ctxPtr;
		foreach_reverse(i, c; contexts) {
			if (value is null) {
				return LLVMConstNull(LLVMPointerType(type, 0));
			}
			
			if (c.type is type) {
				return LLVMBuildPointerCast(builder, value, LLVMPointerType(type, 0), "");
			}
			
			value = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, value, 0, ""), "");
		}
		
		assert(0, "No context available.");
	}
	
	// Figure out what's a good way here.
	LLVMTypeRef define(TypeSymbol s) {
		if (s.hasContext) {
			localData.embededContexts[s] = contexts;
		}
		
		import d.llvm.global;
		return GlobalGen(pass, mode).define(s);
	}
}
