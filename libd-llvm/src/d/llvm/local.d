module d.llvm.local;

import d.llvm.codegen;

import d.ir.dscope;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import llvm.c.core;

alias LocalPass = LocalGen*;

struct LocalGen {
	CodeGenPass pass;
	alias pass this;

	LLVMBuilderRef builder;

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
	
	this(CodeGenPass pass, Closure[] contexts = []) {
		this.pass = pass;
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

	void visit(Symbol s) {
		if (auto v = cast(Variable) s) {
			visit(v);
		} else if (auto f = cast(Function) s) {
			visit(f);
		} else if (auto t = cast(TypeSymbol) s) {
			visit(t);
		} else {
			import d.llvm.global;
			GlobalGen(pass).visit(s);
		}
	}
	
	LLVMValueRef visit(Function f) {
		auto contexts = f.hasContext ? this.contexts : [];
		auto lookup = f.storage.isLocal
			? locals
			: globals;

		return lookup.get(f, {
			auto lg = LocalGen(pass, contexts);
			auto fun = lookup[f] = lg.declare(f);
			
			// We always generate the body for now, but it is very undesirable.
			// FIXME: Separate symbol declaration from symbol definition.
			if (f.fbody) {
				lg.define(f, fun);
			}
			
			return fun;
		} ());
	}
	
	LLVMValueRef declare(Function f) {
		import std.string;
		auto name = f.mangle.toStringz();
		auto type = pass.visit(f.type);

		// The function may have been generated when visiting the type.
		if (auto funPtr = f in globals) {
			return *funPtr;
		}

		// Sanity check.
		auto fun = LLVMGetNamedFunction(dmodule, name);
		assert(!fun, f.mangle ~ " is already declared.");

		return LLVMAddFunction(dmodule, name, LLVMGetElementType(type));
	}

	void define(Function f, LLVMValueRef fun) in {
		assert(LLVMCountBasicBlocks(fun) == 0, f.mangle ~ " body is already defined.");
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
				
				import std.string;
				LLVMSetValueName(value, p.mangle.toStringz());
				locals[p] = value;
			} else {
				assert (p.storage == Storage.Local || p.storage == Storage.Capture, "storage must be local or capture");
				
				auto name = p.name.toString(context);
				p.mangle = name;
				
				import std.string;
				LLVMSetValueName(value, ("arg." ~ name).toStringz());
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
			
			auto vs = cast(VoldemortScope) s.dscope;
			assert(vs, "Struct has context but no VoldemortScope");
			
			buildEmbededCaptures(thisPtr, 0, embededContexts[s], vs);
		} else if (t.kind == TypeKind.Class) {
			auto c = t.dclass;
			if (!c.hasContext) {
				return;
			}
			
			auto vs = cast(VoldemortScope) c.dscope;
			assert(vs, "Class has context but no VoldemortScope");
			
			import d.context.name;
			import std.algorithm, std.range;
			auto f = retro(c.members).filter!(m => m.name == BuiltinName!"__ctx").map!(m => cast(Field) m).front;
			
			buildEmbededCaptures(thisPtr, f.index, embededContexts[c], vs);
		} else {
			assert(0, typeid(t).toString() ~ " is not supported.");
		}
	}
	
	private void buildEmbededCaptures(LLVMValueRef thisPtr, uint i, Closure[] contexts, VoldemortScope s) {
		buildCapturedVariables(LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, thisPtr, i, ""), ""), contexts, s.capture);
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
					import std.string;
					locals[v] = LLVMBuildStructGEP(builder, root, *indexPtr, v.mangle.toStringz());
					
					assert(closureCount > 0, "closureCount is 0 or lower.");
					closureCount--;
				}
			}
			
			root = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, root, 0, ""), "");
		}
		
		assert(closureCount == 0);
	}

	LLVMValueRef visit(Variable v) {
		if (v.storage.isGlobal) {
			import d.llvm.global;
			return GlobalGen(pass).visit(v);
		}

		return locals.get(v, define(v));
	}

	LLVMValueRef define(Variable v) in {
		assert(!v.isFinal);
	} body {
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
			
			import std.string;
			addr = LLVMBuildStructGEP(builder, ctxPtr, closure.indices[v], v.mangle.toStringz());
		} else {
			import std.string;
			addr = LLVMBuildAlloca(builder, type, v.mangle.toStringz());
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

	LLVMTypeRef visit(TypeSymbol s) {
		if (s.hasContext) {
			embededContexts[s] = contexts;
		}
		
		import d.llvm.global;
		return GlobalGen(pass).visit(s);
	}
}