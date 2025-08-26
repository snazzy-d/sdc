module d.llvm.local;

import d.llvm.global;

import d.ir.dscope;
import d.ir.symbol;
import d.ir.type;

import source.location;

import llvm.c.core;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

alias LocalPass = LocalGen*;

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
	GlobalPass pass;
	alias pass this;

	LLVMBuilderRef builder;
	LLVMMetadataRef diScope;

	LLVMValueRef ctxPtr;
	Closure[] contexts;

	LLVMValueRef[ValueSymbol] locals;

	LLVMValueRef lpContext;
	LLVMBasicBlockRef lpBB;

	this(GlobalPass pass, LLVMMetadataRef diScope = null,
	     Closure[] contexts = []) {
		this.pass = pass;
		this.diScope = diScope;
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

	@disable
	this(this);

	// XXX: lack of multiple alias this, so we do it automanually.
	private {
		@property
		ref Closure[][Aggregate] embededContexts() {
			return pass.localData.embededContexts;
		}
	}

	@property
	auto globalGen() {
		return pass;
	}

	void define(Symbol s) {
		if (auto v = cast(Variable) s) {
			define(v);
		} else if (auto f = cast(Function) s) {
			define(f);
		} else if (auto a = cast(Aggregate) s) {
			define(a);
		} else {
			pass.define(s);
		}
	}

	void require(Function f) {
		if (f.step == Step.Processed) {
			return;
		}

		LLVMValueRef[] unreachables;
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		scope(exit) {
			foreach (u; unreachables) {
				LLVMInstructionEraseFromParent(u);
			}

			LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		}

		// OK we need to require. We need to put the module in a good state.
		for (auto fun = LLVMGetFirstFunction(dmodule); fun !is null;
		     fun = LLVMGetNextFunction(fun)) {
			for (auto bb = LLVMGetFirstBasicBlock(fun); bb !is null;
			     bb = LLVMGetNextBasicBlock(bb)) {
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

		auto fun = globals.get(f, {
			auto type = typeGen.getFunctionType(f.type);

			// The method may have been defined when visiting the type.
			if (auto funPtr = f in globals) {
				return *funPtr;
			}

			// Sanity check: do not declare multiple time.
			auto name = f.mangle.toStringz(context);
			auto fun = LLVMGetNamedFunction(dmodule, name);
			if (!fun) {
				fun = LLVMAddFunction(dmodule, name, type);
				LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex,
				                        framePointer);
				return globals[f] = fun;
			}

			if ((!f.fbody || LLVMCountBasicBlocks(fun) == 0)
				    && type == LLVMGlobalGetValueType(fun)) {
				return globals[f] = fun;
			}

			import source.exception, std.format;
			throw new CompileException(
				f.location,
				format!"Invalid redefinition of %s."(
					f.name.toString(pass.context))
			);
		}());

		if (f.hasContext || f.inTemplate || pass.mode == Mode.Eager
			    || (cast(NestedScope) f.getParentScope())) {
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

		import std.format;
		assert(
			LLVMGetLinkage(fun) == LLVMLinkage.LinkOnceODR,
			format!"Function %s is already defined."(f.mangle.toString(context))
		);

		LLVMSetLinkage(fun, LLVMLinkage.External);
		return fun;
	}

	private bool maybeDefine(Function f, LLVMValueRef fun)
			in(f.step == Step.Processed, "f is not processed") {
		auto countBB = LLVMCountBasicBlocks(fun);
		if (countBB > 0) {
			return false;
		}

		// Generate debug infos.
		import d.llvm.debuginfo;
		auto di = DebugInfoScopeGen(pass).define(f);

		import llvm.c.debugInfo;
		LLVMSetSubprogram(fun, di);

		// Generate body.
		auto contexts = f.hasContext ? this.contexts : [];
		LocalGen(pass, di, contexts).genBody(f, fun);

		return true;
	}

	private void genBody(Function f, LLVMValueRef fun) in {
		import std.format;
		assert(
			LLVMCountBasicBlocks(fun) == 0,
			format!"%s body is already defined."(f.mangle.toString(context))
		);

		assert(f.step == Step.Processed, "f is not processed");
		assert(f.fbody || f.intrinsicID, "f must have a body");
	} do {
		scope(failure) f.dump(context);

		// Alloca and instruction block.
		auto allocaBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "");

		// Handle parameters in the alloca block.
		LLVMPositionBuilderAtEnd(builder, allocaBB);

		auto funType = typeGen.getFunctionType(f.type);

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

		auto closure = Closure(f.closure, typeGen.visit(f));
		if (f.hasContext) {
			auto parentCtxType = f.type.parameters[0];
			assert(parentCtxType.isRef || parentCtxType.isFinal);

			auto parentCtx = params[0];
			LLVMSetValueName(parentCtx, "__ctx");

			// Find the right context as parent.
			auto ctxTypeGen = typeGen.visit(parentCtxType.getType());

			import std.algorithm, std.range;
			auto ctxCount = contexts.length
				- retro(contexts).countUntil!(c => c.type is ctxTypeGen)();
			contexts = contexts[0 .. ctxCount];

			buildCapturedVariables(parentCtx, contexts, f.getCaptures());

			// Chain closures.
			ctxPtr = LLVMBuildAlloca(builder, closure.type, "");

			auto ctxStorage =
				LLVMBuildStructGEP2(builder, closure.type, ctxPtr, 0, "");
			LLVMBuildStore(builder, parentCtx, ctxStorage);
			contexts ~= closure;
		} else {
			// Build closure for this function.
			closure.type = typeGen.visit(f);
			contexts = [closure];
		}

		params = params[f.hasContext .. $];
		paramTypes = paramTypes[f.hasContext .. $];

		foreach (i, p; parameters) {
			auto value = params[i];

			auto ptr = createVariableStorage(p, value);
			if (!p.isRef && !p.isFinal) {
				import std.string;
				LLVMSetValueName(value,
				                 toStringz("arg." ~ p.name.toString(context)));
			}

			// This is kind of magic :)
			import source.name;
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
			while (LLVMGetInstructionOpcode(ctxAlloca) != LLVMOpcode.Alloca) {
				assert(
					LLVMGetInstructionOpcode(ctxAlloca) == LLVMOpcode.BitCast);
				ctxAlloca = LLVMGetOperand(ctxAlloca, 0);
			}

			LLVMPositionBuilderBefore(builder, ctxAlloca);

			auto ctxType = contexts[$ - 1].type;

			import d.llvm.runtime;
			auto alloc = RuntimeGen(&this).genGCalloc(ctxType);
			LLVMReplaceAllUsesWith(ctxAlloca, alloc);
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

			import source.name, std.algorithm, std.range;
			auto f = retro(c.fields).filter!(m => m.name == BuiltinName!"__ctx")
			                        .front;

			buildEmbededCaptures(thisPtr, c, f.index);
		} else {
			import std.format;
			assert(0, format!"%s is not supported."(typeid(t)));
		}
	}

	private void buildEmbededCaptures(A)(LLVMValueRef thisPtr, A a, uint i)
			if (is(A : Aggregate)) {
		auto f = a.fields[i];
		assert(f.index == i, "Invalid index!");

		static if (is(A : Class)) {
			auto baseStruct = typeGen.getClassStructure(a);
		} else {
			auto baseStruct = typeGen.visit(a);
		}

		auto rootPtr = LLVMBuildStructGEP2(builder, baseStruct, thisPtr, i, "");
		auto rootType = LLVMStructGetTypeAtIndex(baseStruct, i);
		auto root = LLVMBuildLoad2(builder, rootType, rootPtr, "");
		buildCapturedVariables(root, embededContexts[a], a.getCaptures());
	}

	private void buildCapturedVariables(LLVMValueRef root, Closure[] contexts,
	                                    bool[Variable] capture) {
		auto closureCount = capture.length;

		// Try to find out if we have the variable in a closure.
		foreach_reverse (closure; contexts) {
			if (!closureCount) {
				break;
			}

			// Create enclosed variables.
			foreach (v; capture.byKey()) {
				if (auto indexPtr = v in closure.indices) {
					// Register the variable.
					auto index = *indexPtr;
					auto var = LLVMBuildStructGEP2(builder, closure.type, root,
					                               index, "");

					if (v.isRef || v.isFinal) {
						auto vType =
							LLVMStructGetTypeAtIndex(closure.type, index);
						var = LLVMBuildLoad2(builder, vType, var, "");
					}

					LLVMSetValueName(var, v.mangle.toStringz(context));
					locals[v] = var;

					assert(closureCount > 0, "closureCount is 0 or lower.");
					closureCount--;
				}
			}

			auto rootPtr =
				LLVMBuildStructGEP2(builder, closure.type, root, 0, "");
			auto rootType = LLVMStructGetTypeAtIndex(closure.type, 0);
			root = LLVMBuildLoad2(builder, rootType, rootPtr, "");
		}

		assert(closureCount == 0);
	}

	LLVMValueRef declare(Variable v)
			in(v.storage.isLocal, "globals not supported") {
		// TODO: Actually just declare here :)
		return locals.get(v, define(v));
	}

	LLVMValueRef define(Variable v) in(!v.isFinal && v.storage.isLocal) {
		import d.llvm.expression;
		auto value = v.isRef
			? AddressOfGen(&this).visit(v.value)
			: ExpressionGen(&this).visit(v.value);

		return createVariableStorage(v, value);
	}

	private LLVMValueRef createVariableStorage(Variable v, LLVMValueRef value)
			in(v.storage.isLocal, "globals not supported") {
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
		LLVMPositionBuilderAtEnd(
			builder,
			LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock))
		);

		// Sanity check
		scope(success) {
			assert(LLVMGetInsertBlock(builder) is backupCurrentBlock);
		}

		LLVMValueRef addr = (v.storage == Storage.Capture)
			? createCaptureStorage(v, name)
			: LLVMBuildAlloca(builder, typeGen.visit(v.type), name);

		// Store the initial value into the alloca.
		LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		LLVMBuildStore(builder, value, addr);

		// Register the variable.
		return locals[v] = addr;
	}

	LLVMValueRef createCaptureStorage(Variable v, const char* name)
			in(v.storage == Storage.Capture, "Expected captured") {
		auto closure = &contexts[$ - 1];

		// If we don't have a closure, make one.
		if (ctxPtr is null) {
			ctxPtr = LLVMBuildAlloca(builder, closure.type, "");
		}

		return LLVMBuildStructGEP2(builder, closure.type, ctxPtr,
		                           closure.indices[v], name);
	}

	LLVMValueRef getContext(Function f) {
		auto type = typeGen.visit(f);
		auto value = ctxPtr;
		foreach_reverse (i, c; contexts) {
			if (value is null) {
				return llvmNull;
			}

			if (c.type is type) {
				return value;
			}

			auto ctxPtr = LLVMBuildStructGEP2(builder, c.type, value, 0, "");
			auto ctxType = LLVMStructGetTypeAtIndex(c.type, 0);
			value = LLVMBuildLoad2(builder, ctxType, ctxPtr, "");
		}

		assert(0, "No context available.");
	}

	LLVMTypeRef define(Aggregate a) {
		if (a.hasContext) {
			embededContexts[a] = contexts;
		}

		return pass.define(a);
	}

	/**
	 * Debug helpers.
	 */
	auto enterLocation(Location location) {
		if (diScope is null) {
			return null;
		}

		auto oldLoc = LLVMGetCurrentDebugLocation2(builder);
		auto floc = location.getFullLocation(context);
		auto line = floc.getStartLineNumber();
		auto column = floc.getStartColumn();

		import llvm.c.debugInfo;
		auto loc = LLVMDIBuilderCreateDebugLocation(
			llvmCtx, line, column, diScope, null /* LLVMMetadataRef InlinedAt */
		);
		LLVMSetCurrentDebugLocation2(builder, loc);

		return oldLoc;
	}

	void exitLocation(LLVMMetadataRef oldLoc) {
		if (diScope !is null) {
			LLVMSetCurrentDebugLocation2(builder, oldLoc);
		}
	}
}
