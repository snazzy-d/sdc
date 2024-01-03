module d.llvm.global;

import d.llvm.codegen;

import d.ir.symbol;

import llvm.c.core;

enum Mode {
	Lazy,
	Eager,
}

alias GlobalPass = GlobalGen*;

struct GlobalGen {
	CodeGen pass;
	alias pass this;

	// TODO: Move whatever uses mode in LocalGen here.
	// private:
	Mode mode;

	LLVMValueRef[ValueSymbol] globals;

private:
	Class classInfoClass;
	LLVMValueRef[Class] classInfos;

public:
	import d.llvm.local;
	LocalData localData;

	import d.llvm.constant;
	ConstantData constantData;

	import d.llvm.runtime;
	RuntimeData runtimeData;

	import d.llvm.statement;
	StatementGenData statementGenData;

	import d.llvm.intrinsic;
	IntrinsicGenData intrinsicGenData;

public:
	this(CodeGen pass, string name, Mode mode = Mode.Lazy) {
		this.pass = pass;
		this.mode = mode;

		// Make sure globals are initialized.
		globals[null] = null;
		globals.remove(null);
	}

	@property
	auto typeGen() {
		import d.llvm.type;
		return TypeGen(pass);
	}

	void define(Module m) {
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);

		foreach (s; m.members) {
			define(s);
		}

		checkModule();
	}

	auto checkModule() {
		char* errorPtr;

		import llvm.c.analysis;
		if (!LLVMVerifyModule(dmodule, LLVMVerifierFailureAction.ReturnStatus,
		                      &errorPtr)) {
			return;
		}

		scope(exit) LLVMDisposeMessage(errorPtr);

		import core.stdc.string;
		auto error = errorPtr[0 .. strlen(errorPtr)].idup;
		throw new Exception(error);
	}

	void define(Symbol s) in(s.step == Step.Processed) {
		if (auto f = cast(Function) s) {
			define(f);
		} else if (auto t = cast(Template) s) {
			define(t);
		} else if (auto a = cast(Aggregate) s) {
			define(a);
		} else if (auto v = cast(Variable) s) {
			define(v);
		} else {
			// Some symbol just don't need to generate anything, suck as TypeAlias.
			import std.format;
			assert(true, format!"%s is not supported!"(typeid(s)));
		}
	}

	LLVMValueRef declare(Function f)
			in(!f.hasContext, "Function must not have context!") {
		import d.llvm.local;
		return LocalGen(&this).declare(f);
	}

	LLVMValueRef define(Function f)
			in(!f.hasContext, "Function must not have context!") {
		import d.llvm.local;
		return LocalGen(&this).define(f);
	}

	void define(Template t) {
		foreach (i; t.instances) {
			if (i.hasThis || i.hasContext) {
				continue;
			}

			foreach (m; i.members) {
				import d.llvm.local;
				LocalGen(&this).define(m);
			}
		}
	}

	LLVMTypeRef define(Aggregate a) in(a.step == Step.Processed) {
		if (auto s = cast(Struct) a) {
			return define(s);
		}

		if (auto c = cast(Class) a) {
			return define(c);
		}

		if (auto u = cast(Union) a) {
			return define(u);
		}

		if (auto i = cast(Interface) a) {
			return define(i);
		}

		import std.format;
		assert(0, format!"Aggregate type %s is not supported."(typeid(a)));
	}

	LLVMTypeRef define(Struct s) in(s.step == Step.Processed) {
		foreach (m; s.members) {
			define(m);
		}

		return typeGen.visit(s);
	}

	LLVMTypeRef define(Class c) in(c.step == Step.Processed) {
		// If we are in eager mode, make sure the parent is defined too.
		if (mode == Mode.Eager && c !is c.base) {
			define(c.base);
		}

		// Define virtual methods.
		foreach (m; c.methods) {
			// We don't want to define inherited methods in childs.
			if (!m.hasThis || m.type.parameters[0].getType().dclass is c) {
				define(m);
			}
		}

		// Generate the ClassInfo so we have it even if it is not used.
		// getClassInfo(c);

		// Anything else that could be in there.
		foreach (m; c.members) {
			define(m);
		}

		return typeGen.visit(c);
	}

	LLVMTypeRef define(Union u) in(u.step == Step.Processed) {
		foreach (m; u.members) {
			define(m);
		}

		return typeGen.visit(u);
	}

	LLVMTypeRef define(Interface i) in(i.step == Step.Processed) {
		return typeGen.visit(i);
	}

	private LLVMValueRef genPrimaries(Class c, string mangle) {
		auto count = cast(uint) c.primaries.length;
		auto typeSize = LLVMConstInt(i64, count, false);

		if (count == 0) {
			LLVMValueRef[2] elts = [typeSize, llvmNull];
			return
				LLVMConstStructInContext(llvmCtx, elts.ptr, elts.length, false);
		}

		import std.algorithm, std.array;
		auto parents = c.primaries.map!(p => getClassInfo(p)).array();
		auto gen = LLVMConstArray(llvmPtr, parents.ptr, count);

		import std.string;
		auto type = LLVMArrayType(llvmPtr, count);
		auto primaries =
			LLVMAddGlobal(dmodule, type, toStringz(mangle ~ ".primaries"));
		LLVMSetInitializer(primaries, gen);
		LLVMSetGlobalConstant(primaries, true);
		LLVMSetUnnamedAddr(primaries, true);
		LLVMSetLinkage(primaries, LLVMLinkage.LinkOnceODR);

		LLVMValueRef[2] elts = [typeSize, primaries];
		return LLVMConstStructInContext(llvmCtx, elts.ptr, elts.length, false);
	}

	LLVMValueRef getClassInfo(Class c) in(c.step >= Step.Signed) {
		if (auto ti = c in classInfos) {
			return *ti;
		}

		if (!classInfoClass) {
			classInfoClass = pass.object.getClassInfo();
		}

		auto classInfoStruct = typeGen.getClassStructure(classInfoClass);

		auto methodCount = cast(uint) c.methods.length;
		auto vtblArray = LLVMArrayType(llvmPtr, methodCount);

		LLVMTypeRef[2] classMetadataElts = [classInfoStruct, vtblArray];
		auto metadataStruct =
			LLVMStructTypeInContext(llvmCtx, classMetadataElts.ptr,
			                        classMetadataElts.length, false);

		import std.string;
		auto mangle = c.mangle.toString(context);
		auto metadata =
			LLVMAddGlobal(dmodule, metadataStruct, toStringz(mangle ~ ".vtbl"));
		classInfos[c] = metadata;

		LLVMValueRef[2] classInfoData =
			[getClassInfo(classInfoClass), genPrimaries(c, mangle)];
		auto classInfoGen =
			LLVMConstNamedStruct(classInfoStruct, classInfoData.ptr,
			                     classInfoData.length);

		import std.algorithm, std.array;
		auto methods = c.methods.map!(m => declare(m)).array();
		auto vtbl = LLVMConstArray(llvmPtr, methods.ptr, methodCount);

		LLVMValueRef[2] classDataData = [classInfoGen, vtbl];
		auto metadataGen =
			LLVMConstStructInContext(llvmCtx, classDataData.ptr,
			                         classDataData.length, false);

		LLVMSetInitializer(metadata, metadataGen);
		LLVMSetGlobalConstant(metadata, true);
		LLVMSetLinkage(metadata, LLVMLinkage.LinkOnceODR);

		return metadata;
	}

	LLVMValueRef declare(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} do {
		auto var = globals.get(v, {
			if (v.storage == Storage.Enum) {
				import d.llvm.constant;
				return ConstantGen(&this).visit(v.value);
			}

			return createVariableStorage(v);
		}());

		// Register the variable.
		globals[v] = var;
		if (!v.value || v.storage == Storage.Enum) {
			return var;
		}

		if (v.inTemplate || mode == Mode.Eager) {
			if (maybeDefine(v, var)) {
				LLVMSetLinkage(var, LLVMLinkage.LinkOnceODR);
			}
		}

		return var;
	}

	LLVMValueRef define(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} do {
		auto var = declare(v);
		if (!v.value || v.storage == Storage.Enum) {
			return var;
		}

		if (!maybeDefine(v, var)) {
			import std.format;
			assert(
				LLVMGetLinkage(var) == LLVMLinkage.LinkOnceODR,
				format!"Variable %s already defined!"(
					v.mangle.toString(context))
			);

			LLVMSetLinkage(var, LLVMLinkage.External);
		}

		return var;
	}

	bool maybeDefine(Variable v, LLVMValueRef var) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(v.storage != Storage.Enum, "enum do not have a storage");
		assert(!v.isFinal);
		assert(!v.isRef);
	} do {
		if (LLVMGetInitializer(var)) {
			return false;
		}

		import d.llvm.constant;
		auto value = ConstantGen(&this).visit(v.value);

		// Store the initial value into the global variable.
		LLVMSetInitializer(var, value);
		return true;
	}

	private LLVMValueRef createVariableStorage(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(v.storage != Storage.Enum, "enum do not have a storage");
	} do {
		auto qualifier = v.type.qualifier;

		import d.llvm.type;
		auto type = typeGen.visit(v.type);

		// If it is not enum, it must be static.
		assert(v.storage == Storage.Static);
		auto var = LLVMAddGlobal(dmodule, type, v.mangle.toStringz(context));

		// Depending on the type qualifier,
		// make it thread local/ constant or nothing.
		final switch (qualifier) with (TypeQualifier) {
			case Mutable, Inout, Const:
				LLVMSetThreadLocal(var, true);
				break;

			case Shared, ConstShared:
				break;

			case Immutable:
				LLVMSetGlobalConstant(var, true);
				break;
		}

		return var;
	}
}
