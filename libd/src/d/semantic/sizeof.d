module d.semantic.sizeof;

import d.semantic.semantic;

import d.ir.symbol;
import d.ir.type;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct SizeofVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	uint visit(Type t) {
		return t.accept(this);
	}
	
	uint visit(BuiltinType t) {
		return (t == BuiltinType.Null)
			? getPointerSize()
			: getSize(t);
	}
	
	uint visitPointerOf(Type t) {
		return getPointerSize();
	}
	
	uint visitSliceOf(Type t) {
		return 2 * getPointerSize();
	}
	
	uint visitArrayOf(uint size, Type t) {
		return size * visit(t);
	}
	
	uint visit(Struct s) {
		scheduler.require(s, Step.Signed);
		return dataLayout.getSize(Type.get(s));
	}
	
	uint visit(Class c) {
		return getPointerSize();
	}
	
	uint visit(Enum e) {
		scheduler.require(e);
		return visit(e.type);
	}
	
	uint visit(TypeAlias a) {
		scheduler.require(a);
		return visit(a.type);
	}
	
	uint visit(Interface i) {
		return 2 * getPointerSize();
	}
	
	uint visit(Union u) {
		scheduler.require(u, Step.Signed);
		return dataLayout.getSize(Type.get(u));
	}
	
	uint visit(Function f) {
		assert(0, "context.sizeof is not implemented.");
	}
	
	uint visit(Type[] seq) {
		assert(0, "sequence.sizeof is not implemented.");
	}
	
	uint visit(FunctionType f) {
		auto ptrSize = getPointerSize();
		return (f.contexts.length > 0)
			? 2 * ptrSize
			: ptrSize;
	}
	
	uint visit(TypeTemplateParameter t) {
		assert(0, "Template type has no size.");
	}
	
	import d.context.location, d.context.name;
	uint visitError(Location location, Name name) {
		assert(0, "Error type has no size.");
	}
	
	private uint getPointerSize() {
		return visit(pass.object.getSizeT().type);
	}
}

