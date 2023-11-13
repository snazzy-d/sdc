module d.llvm.global;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct GlobalGenData {
private:
	Class classInfoClass;
	LLVMValueRef[Class] classInfos;
}

struct GlobalGen {
	private CodeGen pass;
	alias pass this;

	import d.llvm.local : Mode;
	Mode mode;

	this(CodeGen pass, Mode mode = Mode.Lazy) {
		this.pass = pass;
		this.mode = mode;
	}

	// XXX: lack of multiple alias this, so we do it automanually.
	private {
		@property
		ref Class classInfoClass() {
			return pass.globalGenData.classInfoClass;
		}

		@property
		ref LLVMValueRef[Class] classInfos() {
			return pass.globalGenData.classInfos;
		}
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
		}
	}

	LLVMValueRef declare(Function f)
			in(!f.hasContext, "function must not have context") {
		import d.llvm.local;
		return LocalGen(pass).declare(f);
	}

	LLVMValueRef define(Function f)
			in(!f.hasContext, "function must not have context") {
		import d.llvm.local;
		return LocalGen(pass).define(f);
	}

	LLVMValueRef declare(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} do {
		auto var = globals.get(v, {
			if (v.storage == Storage.Enum) {
				import d.llvm.constant;
				return ConstantGen(pass).visit(v.value);
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
			auto linkage = LLVMGetLinkage(var);
			assert(
				linkage == LLVMLinkage.LinkOnceODR,
				"variable " ~ v.mangle.toString(context) ~ " already defined"
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
		auto value = ConstantGen(pass).visit(v.value);

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
		auto type = TypeGen(pass).visit(v.type);

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

	LLVMTypeRef define(Aggregate a) in(a.step == Step.Processed) {
		return this.dispatch(a);
	}

	LLVMTypeRef visit(Struct s) in(s.step == Step.Processed) {
		import d.llvm.type;
		auto ret = TypeGen(pass).visit(s);

		foreach (m; s.members) {
			define(m);
		}

		return ret;
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
			LLVMAddGlobal(dmodule, type, toStringz(mangle ~ "__primaries"));
		LLVMSetInitializer(primaries, gen);
		LLVMSetGlobalConstant(primaries, true);
		LLVMSetUnnamedAddr(primaries, true);
		LLVMSetLinkage(primaries, LLVMLinkage.LinkOnceODR);

		LLVMValueRef[2] elts = [typeSize, primaries];
		return LLVMConstStructInContext(llvmCtx, elts.ptr, elts.length, false);
	}

	// FIXME: This is only useful as a public method because of downcast.
	// As downcast is moved to being implemented in the runtime rather
	// than in the codegen, this can be made private.
	LLVMTypeRef getClassInfoStructure() {
		if (!classInfoClass) {
			classInfoClass = pass.object.getClassInfo();
		}

		import d.llvm.type;
		return TypeGen(pass).getClassStructure(classInfoClass);
	}

	LLVMValueRef getClassInfo(Class c) in(c.step >= Step.Signed) {
		if (auto ti = c in classInfos) {
			return *ti;
		}

		import std.string;
		auto mangle = c.mangle.toString(context);
		auto metadataStruct =
			LLVMStructCreateNamed(llvmCtx, toStringz(mangle ~ "__metadata"));

		auto methodCount = cast(uint) c.methods.length;
		auto classInfoStruct = getClassInfoStructure();
		auto vtblArray = LLVMArrayType(llvmPtr, methodCount);
		LLVMTypeRef[2] classMetadataElts = [classInfoStruct, vtblArray];
		LLVMStructSetBody(metadataStruct, classMetadataElts.ptr,
		                  classMetadataElts.length, false);

		auto metadata = LLVMAddGlobal(dmodule, metadataStruct,
		                              toStringz(mangle ~ "__vtbl"));
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
			LLVMConstNamedStruct(metadataStruct, classDataData.ptr,
			                     classDataData.length);

		LLVMSetInitializer(metadata, metadataGen);
		LLVMSetGlobalConstant(metadata, true);
		LLVMSetLinkage(metadata, LLVMLinkage.LinkOnceODR);

		return metadata;
	}

	LLVMTypeRef visit(Class c) in(c.step == Step.Processed) {
		import d.llvm.type;
		auto ret = TypeGen(pass).visit(c);

		foreach (m; c.methods) {
			// We don't want to define inherited methods in childs.
			if (!m.hasThis || m.type.parameters[0].getType().dclass is c) {
				define(m);
			}
		}

		foreach (m; c.members) {
			define(m);
		}

		return ret;
	}

	LLVMTypeRef visit(Union u) in(u.step == Step.Processed) {
		import d.llvm.type;
		auto ret = TypeGen(pass).visit(u);

		foreach (m; u.members) {
			define(m);
		}

		return ret;
	}

	LLVMTypeRef visit(Interface i) in(i.step == Step.Processed) {
		import d.llvm.type;
		return TypeGen(pass).visit(i);
	}

	void define(Template t) {
		foreach (i; t.instances) {
			if (i.hasThis || i.hasContext) {
				continue;
			}

			foreach (m; i.members) {
				import d.llvm.local;
				LocalGen(pass).define(m);
			}
		}
	}
}
