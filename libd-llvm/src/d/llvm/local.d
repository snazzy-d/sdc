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

struct LocalGen {
	CodeGenPass pass;
	alias pass this;
	
	LLVMBuilderRef builder;
	
	Mode mode;
	
	LLVMValueRef thisPtr;
	LLVMValueRef ctxPtr;
	
	LLVMValueRef[ValueSymbol] locals;
	
	alias Closure = CodeGenPass.Closure;
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
	
	this(CodeGenPass pass, Mode mode = Mode.Lazy, Closure[] contexts = []) {
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
			auto type = LLVMGetElementType(pass.visit(f.type));
			
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
		
		thisPtr = null;
		if (f.hasThis) {
			// TODO: if this have a context, expand variables !
			auto thisType = f.type.parameters[0];
			auto value = params[0];
			
			if (thisType.isRef || thisType.isFinal) {
				LLVMSetValueName(value, "this");
				thisPtr = value;
			} else {
				auto alloca = LLVMBuildAlloca(builder, paramTypes[0], "this");
				LLVMSetValueName(value, "arg.this");
				
				LLVMBuildStore(builder, value, alloca);
				thisPtr = alloca;
			}
			
			buildEmbededCaptures(thisPtr, thisType.getType());
			
			params = params[1 .. $];
			paramTypes = paramTypes[1 .. $];
		}

		auto closure = Closure(f.closure, buildContextType(f));
		if (f.hasContext) {
			auto parentCtxType = f.type.parameters[f.hasThis];
			assert(parentCtxType.isRef || parentCtxType.isFinal);
			
			auto parentCtx = params[f.hasThis];
			LLVMSetValueName(parentCtx, "__ctx");
			
			// Find the right context as parent.
			import std.algorithm, std.range;
			auto ctxTypeGen = pass.visit(parentCtxType.getType());
			contexts = contexts[0 .. $ - retro(contexts).countUntil!(c => c.type is ctxTypeGen)()];
			
			auto s = cast(ClosureScope) f.dscope;
			assert(s, "Function has context but do not have a closure scope");
			
			buildCapturedVariables(parentCtx, contexts, s.capture);
			
			params = params[1 .. $];
			paramTypes = paramTypes[1 .. $];
			
			// Chain closures.
			ctxPtr = LLVMBuildAlloca(builder, closure.type, "");
			
			LLVMBuildStore(builder, parentCtx, LLVMBuildStructGEP(builder, ctxPtr, 0, ""));
			contexts ~= closure;
		} else {
			// Build closure for this function.
			closure.type = buildContextType(f);
			contexts = [closure];
		}
		
		foreach(i, p; parameters) {
			auto type = p.type;
			auto value = params[i];
			
			if (p.isRef || p.isFinal) {
				assert (p.storage == Storage.Local, "storage must be local");
				
				LLVMSetValueName(value, p.name.toStringz(context));
				locals[p] = value;
			} else {
				assert (p.storage == Storage.Local || p.storage == Storage.Capture, "storage must be local or capture");
				
				import std.string;
				LLVMSetValueName(value, toStringz("arg." ~ p.name.toString(context)));
				createVariableStorage(p, value);
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
			
			import d.llvm.expression;
			auto alloc = ExpressionGen(&this).buildCall(druntimeGen.getAllocMemory(), [LLVMSizeOf(ctxType)]);
			LLVMAddInstrAttribute(alloc, 0, LLVMAttribute.NoAlias);
			
			LLVMReplaceAllUsesWith(ctxAlloca, LLVMBuildPointerCast(builder, alloc, LLVMPointerType(ctxType, 0), ""));
		}
	}

	private void buildEmbededCaptures(LLVMValueRef thisPtr, Type t) {
		if (t.kind == TypeKind.Struct) {
			auto s = t.dstruct;
			if (!s.hasContext) {
				return;
			}
			
			auto vs = cast(ClosureScope) s.dscope;
			assert(vs, "Struct has context but no VoldemortScope");
			
			buildEmbededCaptures(thisPtr, 0, embededContexts[s], vs);
		} else if (t.kind == TypeKind.Class) {
			auto c = t.dclass;
			if (!c.hasContext) {
				return;
			}
			
			auto vs = cast(ClosureScope) c.dscope;
			assert(vs, "Class has context but no VoldemortScope");
			
			import d.context.name;
			import std.algorithm, std.range;
			auto f = retro(c.members).filter!(m => m.name == BuiltinName!"__ctx").map!(m => cast(Field) m).front;
			
			buildEmbededCaptures(thisPtr, f.index, embededContexts[c], vs);
		} else {
			assert(0, typeid(t).toString() ~ " is not supported.");
		}
	}
	
	private void buildEmbededCaptures(LLVMValueRef thisPtr, uint i, Closure[] contexts, ClosureScope s) {
		buildCapturedVariables(LLVMBuildLoad(
			builder,
			LLVMBuildStructGEP(builder, thisPtr, i, ""),
			"",
		), contexts, s.capture);
	}
	
	private void buildCapturedVariables(LLVMValueRef root, Closure[] contexts, bool[Variable] capture) {
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
					locals[v] = LLVMBuildStructGEP(
						builder,
						root,
						*indexPtr,
						v.mangle.toStringz(context),
					);
					
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

	private LLVMValueRef createVariableStorage(Variable v, LLVMValueRef value) in {
		assert(v.storage.isLocal, "globals not supported");
	} body {
		if (v.isRef) {
			return locals[v] = value;
		}
		
		auto qualifier = v.type.qualifier;
		auto type = pass.visit(v.type);

		// Backup current block
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
		
		// Sanity check
		scope(success) assert(LLVMGetInsertBlock(builder) is backupCurrentBlock);
		
		LLVMValueRef addr;
		if (v.storage == Storage.Capture) {
			auto closure = &contexts[$ - 1];
			
			// If we don't have a closure, make one.
			if (ctxPtr is null) {
				ctxPtr = LLVMBuildAlloca(builder, closure.type, "");
				auto ctxType = LLVMStructTypeInContext(llvmCtx, &type, 1, false);
			}
			
			addr = LLVMBuildStructGEP(
				builder,
				ctxPtr,
				closure.indices[v],
				v.mangle.toStringz(context),
			);
		} else {
			addr = LLVMBuildAlloca(builder, type, v.mangle.toStringz(context));
		}
		
		// Store the initial value into the alloca.
		LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		LLVMBuildStore(builder, value, addr);
		
		import d.context.name;
		if (v.name == BuiltinName!"this") {
			thisPtr = addr;
		}
		
		// Register the variable.
		return locals[v] = addr;
	}

	LLVMValueRef getContext(Function f) {
		auto type = buildContextType(f);
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
	LLVMTypeRef visit(Type t) {
		return pass.visit(t);
	}

	LLVMTypeRef visit(FunctionType t) {
		return pass.visit(t);
	}

	LLVMTypeRef define(TypeSymbol s) {
		if (s.hasContext) {
			embededContexts[s] = contexts;
		}
		
		import d.llvm.global;
		return GlobalGen(pass, mode).define(s);
	}
}