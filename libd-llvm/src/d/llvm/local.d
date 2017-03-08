module d.llvm.local;

import d.llvm.codegen;

import d.ir.dscope;
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
	Closure[][Aggregate] embededContexts;
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
	LLVMBasicBlockRef lpBB;
	
	this(CodeGen pass, Mode mode = Mode.Lazy, Closure[] contexts = []) {
		this.pass = pass;
		this.mode = mode;
		this.contexts = contexts;
		
		// Make sure locals are initialized.
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
		} else if (auto a = cast(Aggregate) s) {
			define(a);
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
		
		// XXX: This should probably a member of the Function class.
		auto isLocal = f.hasContext || (cast(NestedScope) f.getParentScope());
		auto lookup = isLocal ? locals : globals;
		
		// FIXME: This is broken, but we do it all in globals for now.
		// We have no good way to pas the nested locals down in aggregates
		// declarations as we do a round trip through globals.
		// We could fix this by removing any require from the backend
		// and moving local to the localData, or bubbling down part of the
		// aggregate declaration code in the LocalGen. This last option seems
		// more reasonable as the situation is also broken for embededContexts.
		// In the meantime, just store everything in globals.
		lookup = globals;
		
		auto fun = lookup.get(f, {
			auto name = f.mangle.toStringz(pass.context);
			
			import d.llvm.type;
			auto type = LLVMGetElementType(TypeGen(pass).visit(f.type));
			
			// The method may have been defined when visiting the type.
			if (auto funPtr = f in lookup) {
				return *funPtr;
			}
			
			// Sanity check: do not declare multiple time.
			assert(
				!LLVMGetNamedFunction(pass.dmodule, name),
				f.mangle.toString(pass.context) ~ " is already declared.",
			);
			
			return lookup[f] = LLVMAddFunction(pass.dmodule, name, type);
		} ());
		
		if (isLocal || f.inTemplate || mode == Mode.Eager) {
			if (f.fbody && maybeDefine(f, fun)) {
				LLVMSetLinkage(fun, LLVMLinkage.LinkOnceODR);
			}
		}
		
		return fun;
	}
	
	LLVMValueRef define(Function f) {
		auto fun = declare(f);
		if (!f.fbody && !f.intrinsicID) {
			return fun;
		}
		
		if (maybeDefine(f, fun)) {
			return fun;
		}
		
		auto linkage = LLVMGetLinkage(fun);
		assert(
			linkage == LLVMLinkage.LinkOnceODR,
			"function " ~ f.mangle.toString(context) ~ " already defined"
		);
		
		LLVMSetLinkage(fun, LLVMLinkage.External);
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
		assert(
			LLVMCountBasicBlocks(fun) == 0,
			f.mangle.toString(context) ~ " body is already defined"
		);
		
		assert(f.step == Step.Processed, "f is not processed");
		assert(f.fbody || f.intrinsicID, "f must have a body");
	} body {
		scope(failure) f.dump(context);
		
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
		
		// If this function is a known intrinsic, swap implementation.
		if (f.intrinsicID) {
			import d.llvm.expression, d.llvm.intrinsic;
			LLVMBuildRet(
				builder,
				ExpressionGen(&this).buildBitCast(
					IntrinsicGen(&this).build(f.intrinsicID, params),
					LLVMGetReturnType(funType),
				),
			);
			return;
		}
		
		auto parameters = f.params;
		
		import d.llvm.type;
		auto closure = Closure(f.closure, TypeGen(pass).visit(f));
		if (f.hasContext) {
			auto parentCtxType = f.type.parameters[0];
			assert(parentCtxType.isRef || parentCtxType.isFinal);
			
			auto parentCtx = params[0];
			LLVMSetValueName(parentCtx, "__ctx");
			
			// Find the right context as parent.
			import d.llvm.type;
			auto ctxTypeGen = TypeGen(pass).visit(parentCtxType.getType());
			
			import std.algorithm, std.range;
			auto ctxCount = contexts.length -
				retro(contexts).countUntil!(c => c.type is ctxTypeGen)();
			contexts = contexts[0 .. ctxCount];
			
			buildCapturedVariables(parentCtx, contexts, f.getCaptures());
			
			// Chain closures.
			ctxPtr = LLVMBuildAlloca(builder, closure.type, "");
			
			auto ctxStorage = LLVMBuildStructGEP(builder, ctxPtr, 0, "");
			LLVMBuildStore(builder, parentCtx, ctxStorage);
			contexts ~= closure;
		} else {
			// Build closure for this function.
			import d.llvm.type;
			closure.type = TypeGen(pass).visit(f);
			contexts = [closure];
		}
		
		params = params[f.hasContext .. $];
		paramTypes = paramTypes[f.hasContext .. $];
		
		foreach(i, p; parameters) {
			auto value = params[i];
			
			auto ptr = createVariableStorage(p, value);
			if (!p.isRef && !p.isFinal) {
				import std.string;
				LLVMSetValueName(
					value,
					toStringz("arg." ~ p.name.toString(context)),
				);
			}
			
			// this is kind of magic :)
			import d.context.name;
			if (p.name == BuiltinName!"this") {
				buildEmbededCaptures(ptr, p.type);
			}
		}
		
		// Generate function's body.
		import d.llvm.statement;
		StatementGen(&this).visit(f.fbody);
		
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
			auto alloc = ExpressionGen(&this).buildCall(
				RuntimeGen(pass).getAllocMemory(),
				[LLVMSizeOf(ctxType)],
			);
			
			// XXX: This should be set on the alloc function instead of the callsite.
			LLVMAddCallSiteAttribute(
				alloc,
				LLVMAttributeReturnIndex,
				getAttribute("noalias"),
			);
			
			LLVMReplaceAllUsesWith(ctxAlloca, LLVMBuildPointerCast(
				builder,
				alloc,
				LLVMPointerType(ctxType, 0),
				"",
			));
		}
	}
	
	private void buildEmbededCaptures(LLVMValueRef thisPtr, Type t) {
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
			
			auto rootPtr = LLVMBuildStructGEP(builder, root, 0, "");
			root = LLVMBuildLoad(builder, rootPtr, "");
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
		auto name = v.name.toStringz(context);
		
		if (v.isRef || v.isFinal) {
			if (v.storage == Storage.Capture) {
				auto addr = createCaptureStorage(v, "");
				LLVMBuildStore(builder, value, addr);
			}
			
			if (LLVMGetValueName(value)[0] == '\0') {
				LLVMSetValueName(value, name);
			}
			
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
				auto ptrType = LLVMPointerType(type, 0);
				return LLVMBuildPointerCast(builder, value, ptrType, "");
			}
			
			auto ctxPtr = LLVMBuildStructGEP(builder, value, 0, "");
			value = LLVMBuildLoad(builder, ctxPtr, "");
		}
		
		assert(0, "No context available.");
	}
	
	LLVMTypeRef define(Aggregate a) {
		if (a.hasContext) {
			localData.embededContexts[a] = contexts;
		}
		
		import d.llvm.global;
		return GlobalGen(pass, mode).define(a);
	}
}
