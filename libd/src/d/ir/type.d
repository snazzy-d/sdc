module d.ir.type;

import d.ir.symbol;

public import d.common.builtintype;
public import d.common.qualifier;

import d.context.name;
import d.context.location;
import d.common.type;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

enum TypeKind : ubyte {
	Builtin,
	
	// Symbols
	Alias,
	Struct,
	Class,
	Interface,
	Union,
	Enum,
	
	// Context
	Context,
	
	// Type constructors
	Pointer,
	Slice,
	Array,
	
	// Sequence
	Sequence,
	
	// Complex types
	Function,
	
	// Template type
	Template,
	
	// Error
	Error,
}

struct Type {
private:
	mixin TypeMixin!(TypeKind, Payload);
	
	this(Desc d, inout Payload p = Payload.init) inout {
		desc = d;
		payload = p;
	}
	
	import util.fastcast;
	this(Desc d, inout Symbol s) inout {
		this(d, fastCast!(inout Payload)(s));
	}
	
	this(Desc d, inout Type* t) inout {
		this(d, fastCast!(inout Payload)(t));
	}
	
	this(Desc d, inout Location l) inout {
		this(d, fastCast!(inout Payload)(l));
	}
	
	Type getConstructedType(this T)(TypeKind k, TypeQualifier q) {
		return qualify(q).getConstructedMixin(k, q);
	}
	
	auto acceptImpl(T)(T t) {
		final switch(kind) with(TypeKind) {
			case Builtin :
				return t.visit(builtin);
			
			case Struct :
				return t.visit(dstruct);
			
			case Class :
				return t.visit(dclass);
			
			case Enum :
				return t.visit(denum);
			
			case Alias :
				// XXX: consider how to propagate the qualifier properly.
				return t.visit(dalias);
			
			case Interface :
				return t.visit(dinterface);
			
			case Union :
				return t.visit(dunion);
			
			case Context :
				return t.visit(context);
			
			case Pointer :
				return t.visitPointerOf(element);
			
			case Slice :
				return t.visitSliceOf(element);
			
			case Array :
				return t.visitArrayOf(size, element);
			
			case Sequence :
				return t.visit(sequence);
			
			case Function :
				return t.visit(asFunctionType());
			
			case Template :
				return t.visit(dtemplate);
			
			case Error :
				return t.visitError(location, message);
		}
	}
	
public:
	auto accept(T)(ref T t) if(is(T == struct)) {
		return acceptImpl(&t);
	}
	
	auto accept(T)(T t) if(is(T == class)) {
		return acceptImpl(t);
	}
	
	Type qualify(TypeQualifier q) {
		auto nq = q.add(qualifier);
		if (nq == qualifier) {
			return Type(desc, payload);
		}
		
		switch(kind) with(TypeKind) {
			case Builtin, Struct, Class, Enum, Alias, Interface, Union, Context, Function :
				auto d = desc;
				d.qualifier = nq;
				return Type(d, payload);
			
			case Pointer :
				return element.qualify(nq).getPointer(nq);
			
			case Slice :
				return element.qualify(nq).getSlice(nq);
			
			case Array :
				return element.qualify(nq).getArray(size, nq);
			
			default :
				assert(0, "Not implemented");
		}
	}
	
	Type unqual() {
		auto d = desc;
		d.qualifier = TypeQualifier.Mutable;
		return Type(d, payload);
	}
	
	@property
	BuiltinType builtin() inout in {
		assert(kind == TypeKind.Builtin, "Not a builtin type.");
	} body {
		return cast(BuiltinType) desc.data;
	}
	
	bool isAggregate() const {
		return (kind >= TypeKind.Struct) && (kind <= TypeKind.Union);
	}
	
	@property
	auto aggregate() inout in {
		assert(isAggregate, "Not an aggregate type.");
	} body {
		return payload.agg;
	}
	
	@property
	auto dstruct() inout in {
		assert(kind == TypeKind.Struct);
	} body {
		return payload.dstruct;
	}
	
	@property
	auto dclass() inout in {
		assert(kind == TypeKind.Class);
	} body {
		return payload.dclass;
	}
	
	@property
	auto denum() inout in {
		assert(kind == TypeKind.Enum);
	} body {
		return payload.denum;
	}
	
	auto getCanonicalAndPeelEnum() {
		auto t = this.getCanonical();
		auto q = qualifier;
		while(t.kind == TypeKind.Enum) {
			t = t.denum.type.getCanonical();
			q = q.add(t.qualifier);
		}
		
		return t.qualify(q);
	}
	
	@property
	auto dalias() inout in {
		assert(kind == TypeKind.Alias);
	} body {
		return payload.dalias;
	}
	
	auto getCanonical() {
		auto t = this;
		auto q = qualifier;
		while(t.kind == TypeKind.Alias) {
			t = t.dalias.type;
			q = q.add(t.qualifier);
		}
		
		return t.qualify(q);
	}
	
	@property
	auto dinterface() inout in {
		assert(kind == TypeKind.Interface);
	} body {
		return payload.dinterface;
	}
	
	@property
	auto dunion() inout in {
		assert(kind == TypeKind.Union);
	} body {
		return payload.dunion;
	}
	
	@property
	auto context() inout in {
		assert(kind == TypeKind.Context);
	} body {
		return payload.context;
	}
	
	@property
	auto dtemplate() inout in {
		assert(kind == TypeKind.Template);
	} body {
		return payload.dtemplate;
	}
	
	@property
	auto location() inout in {
		assert(kind == TypeKind.Error);
	} body {
		return payload.location;
	}
	
	@property
	auto message() inout in {
		assert(kind == TypeKind.Error);
	} body {
		assert(desc.data <= uint.max);
		auto rawname = cast(uint) desc.data;
		return *(cast(Name*) &rawname);
	}
	
	Type getPointer(TypeQualifier q = TypeQualifier.Mutable) {
		return getConstructedType(TypeKind.Pointer, q);
	}
	
	Type getSlice(TypeQualifier q = TypeQualifier.Mutable) {
		return getConstructedType(TypeKind.Slice, q);
	}
	
	Type getArray(uint size, TypeQualifier q = TypeQualifier.Mutable) {
		auto t = qualify(q);
		
		// XXX: Consider caching in context.
		auto n = new Type(t.desc, t.payload);
		return Type(Desc(TypeKind.Array, q, size), n);
	}
	
	bool hasElement() const {
		return (kind >= TypeKind.Pointer) && (kind <= TypeKind.Array);
	}
	
	@property
	auto element() inout in {
		assert(hasElement, "element called on a type with no element.");
	} body {
		if (kind == TypeKind.Array) {
			return *payload.next;
		}
		
		return getElementMixin();
	}
	
	@property
	uint size() const in {
		assert(kind == TypeKind.Array, "Only array have size.");
	} body {
		assert(desc.data <= uint.max);
		return cast(uint) desc.data;
	}
	
	@property
	auto sequence() inout in {
		assert(kind == TypeKind.Sequence, "Not a sequence type.");
	} body {
		return payload.next[0 .. desc.data];
	}
	
	bool hasPointerABI() const {
		switch (kind) with(TypeKind) {
			case Class, Pointer :
				return true;
			
			case Alias :
				return dalias.type.hasPointerABI();
			
			case Function :
				return asFunctionType().contexts.length == 0;
			
			default :
				return false;
		}
	}
	
	string toString(const ref NameManager nm, TypeQualifier q = TypeQualifier.Mutable) const {
		auto s = toUnqualString(nm);
		if (q == qualifier) {
			return s;
		}
		
		final switch(qualifier) with(TypeQualifier) {
			case Mutable:
				return s;
			
			case Inout:
				return "inout(" ~ s ~ ")";
			
			case Const:
				return "const(" ~ s ~ ")";
			
			case Shared:
				return "shared(" ~ s ~ ")";
			
			case ConstShared:
				assert(0, "const shared isn't supported");
			
			case Immutable:
				return "immutable(" ~ s ~ ")";
		}
	}
	
	string toUnqualString(const ref NameManager nm) const {
		final switch(kind) with(TypeKind) {
			case Builtin :
				import d.common.builtintype : toString;
				return toString(builtin);
			
			case Struct :
				return dstruct.name.toString(nm);
			
			case Class :
				return dclass.name.toString(nm);
			
			case Enum :
				return denum.name.toString(nm);
			
			case Alias :
				return dalias.name.toString(nm);
			
			case Interface :
				return dinterface.name.toString(nm);
			
			case Union :
				return dunion.name.toString(nm);
			
			case Context :
				return "__ctx";
			
			case Pointer :
				return element.toString(nm, qualifier) ~ "*";
			
			case Slice :
				return element.toString(nm, qualifier) ~ "[]";
			
			case Array :
				import std.conv;
				return element.toString(nm, qualifier) ~ "[" ~ to!string(size) ~ "]";
			
			case Sequence :
				import std.algorithm, std.range;
				// XXX: need to use this because of identifier hijacking in the import.
				return this.sequence.map!(e => e.toString(nm, qualifier)).join(", ");
			
			case Function :
				auto f = asFunctionType();
				auto ret = f.returnType.toString(nm);
				auto base = f.contexts.length ? " delegate(" : " function(";
				import std.algorithm, std.range;
				auto args = f.parameters.map!(p => p.toString(nm)).join(", ");
				return ret ~ base ~ args ~ (f.isVariadic ? ", ...)" : ")");
			
			case Template :
				return dtemplate.name.toString(nm);
			
			case Error :
				return "__error__(" ~ message.toString(nm) ~ ")";
		}
	}
	
static:
	Type get(BuiltinType bt, TypeQualifier q = TypeQualifier.Mutable) {
		Payload p; // Needed because of lolbug in inout
		return Type(Desc(TypeKind.Builtin, q, bt), p);
	}
	
	Type get(Struct s, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Struct, q), s);
	}
	
	Type get(Class c, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Class, q), c);
	}
	
	Type get(Enum e, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Enum, q), e);
	}
	
	Type get(TypeAlias a, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Alias, q), a);
	}
	
	Type get(Interface i, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Interface, q), i);
	}
	
	Type get(Union u, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Union, q), u);
	}
	
	Type get(Type[] elements, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Sequence, q, elements.length), elements.ptr);
	}
	
	Type get(TypeTemplateParameter p, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Template, q), p);
	}
	
	Type getContextType(Function f, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Context, q), f);
	}
	
	Type getError(Location location, Name message, TypeQualifier q = TypeQualifier.Mutable) {
		static assert(Name.sizeof == uint.sizeof);
		return Type(Desc(TypeKind.Error, q, *(cast(uint*) &message)), location);
	}
}

unittest {
	auto i = Type.get(BuiltinType.Int);
	auto pi = i.getPointer();
	assert(i == pi.element);
	
	auto ci = i.qualify(TypeQualifier.Const);
	auto cpi = pi.qualify(TypeQualifier.Const);
	assert(ci == cpi.element);
	assert(i != cpi.element);
}

unittest {
	auto i = Type.get(BuiltinType.Int);
	auto t = i;
	foreach(_; 0 .. 64) {
		t = t.getPointer().getSlice();
	}
	
	foreach(_; 0 .. 64) {
		assert(t.kind == TypeKind.Slice);
		t = t.element;
		assert(t.kind == TypeKind.Pointer);
		t = t.element;
	}
	
	assert(t == i);
}

unittest {
	auto i = Type.get(BuiltinType.Int);
	auto ai = i.getArray(42);
	assert(i == ai.element);
	assert(ai.size == 42);
}

unittest {
	auto i = Type.get(BuiltinType.Int);
	auto ci = Type.get(BuiltinType.Int, TypeQualifier.Const);
	auto cpi = i.getPointer(TypeQualifier.Const);
	assert(ci == cpi.element);
	
	auto csi = i.getSlice(TypeQualifier.Const);
	assert(ci == csi.element);
	
	auto cai = i.getArray(42, TypeQualifier.Const);
	assert(ci == cai.element);
}

unittest {
	import d.context.location, d.context.name, d.ir.symbol;
	auto c = new Class(Location.init, BuiltinName!"", []);
	auto tc = Type.get(c);
	assert(tc.isAggregate);
	assert(tc.aggregate is c);
	
	auto cc = Type.get(c, TypeQualifier.Const);
	auto csc = tc.getSlice(TypeQualifier.Const);
	assert(cc == csc.element);
}

unittest {
	import d.context.location, d.context.name, d.ir.symbol;
	auto i = Type.get(BuiltinType.Int);
	auto a1 = new TypeAlias(Location.init, BuiltinName!"", i);
	auto a1t = Type.get(a1);
	assert(a1t.getCanonical() == i);

	auto a2 = new TypeAlias(Location.init, BuiltinName!"", a1t);
	auto a2t = Type.get(a2, TypeQualifier.Immutable);
	assert(a2t.getCanonical() == i.qualify(TypeQualifier.Immutable));

	auto a3 = new TypeAlias(Location.init, BuiltinName!"", a2t);
	auto a3t = Type.get(a3, TypeQualifier.Const);
	assert(a3t.getCanonical() == i.qualify(TypeQualifier.Immutable));
}

unittest {
	import d.context.location, d.context.name, d.ir.symbol;
	auto f = Type.get(BuiltinType.Float, TypeQualifier.Const);
	auto a = new TypeAlias(Location.init, BuiltinName!"", f);
	
	auto e1 = new Enum(Location.init, BuiltinName!"", Type.get(a), []);
	auto e1t = Type.get(e1);
	assert(e1t.getCanonicalAndPeelEnum() == f);

	auto e2 = new Enum(Location.init, BuiltinName!"", e1t, []);
	auto e2t = Type.get(e2, TypeQualifier.Immutable);
	assert(e2t.getCanonicalAndPeelEnum() == f.qualify(TypeQualifier.Immutable));

	auto e3 = new Enum(Location.init, BuiltinName!"", e2t, []);
	auto e3t = Type.get(e3, TypeQualifier.Const);
	assert(e3t.getCanonicalAndPeelEnum() == f.qualify(TypeQualifier.Immutable));
}

alias ParamType = Type.ParamType;

string toString(const ParamType t, const ref NameManager nm) {
	string s;
	if (t.isRef && t.isFinal) {
		s = "final ref ";
	} else if (t.isRef) {
		s = "ref ";
	} else if (t.isFinal) {
		s = "final ";
	}
	
	return s ~ t.getType().toString(nm);
}

inout(ParamType) getParamType(inout ParamType t, bool isRef, bool isFinal) {
	return t.getType().getParamType(isRef, isFinal);
}

unittest {
	auto pi = Type.get(BuiltinType.Int).getPointer(TypeQualifier.Const);
	auto p = pi.getParamType(true, false);
	
	assert(p.isRef == true);
	assert(p.isFinal == false);
	assert(p.qualifier == TypeQualifier.Const);
	
	auto pt = p.getType();
	assert(pt == pi);
}

alias FunctionType = Type.FunctionType;

unittest {
	auto r = Type.get(BuiltinType.Void).getPointer().getParamType(false, false);
	auto c = Type.get(BuiltinType.Null).getSlice().getParamType(false, true);
	auto p = Type.get(BuiltinType.Float).getSlice(TypeQualifier.Immutable).getParamType(true, true);
	auto f = FunctionType(Linkage.Java, r, [c, p], true);
	
	assert(f.linkage == Linkage.Java);
	assert(f.isVariadic == true);
	assert(f.isPure == false);
	assert(f.returnType == r);
	assert(f.parameters.length == 2);
	assert(f.parameters[0] == c);
	assert(f.parameters[1] == p);
	
	auto ft = f.getType();
	assert(ft.asFunctionType() == f);
	
	auto d = f.getDelegate();
	assert(d.linkage == Linkage.Java);
	assert(d.isVariadic == true);
	assert(d.isPure == false);
	assert(d.returnType == r);
	assert(d.contexts.length == 1);
	assert(d.contexts[0] == c);
	assert(d.parameters.length == 1);
	assert(d.parameters[0] == p);
	
	auto dt = d.getType();
	assert(dt.asFunctionType() == d);
	assert(dt.asFunctionType() != f);
	
	auto d2 = d.getDelegate(2);
	assert(d2.contexts.length == 2);
	assert(d2.parameters.length == 0);
	assert(d2.getDelegate(0) == f);
}

private:

// XXX: we put it as a UFCS property to avoid forward reference.
@property
inout(ParamType)* params(inout Payload p) {
	import util.fastcast;
	return cast(inout ParamType*) p.next;
}

union Payload {
	Type* next;
	
	// Symbols
	TypeAlias dalias;
	Class dclass;
	Interface dinterface;
	Struct dstruct;
	Union dunion;
	Enum denum;
	
	// Context
	Function context;
	
	// For function and delegates.
	// ParamType* params;
	
	// For template instanciation.
	TypeTemplateParameter dtemplate;
	
	// Location are useful for errors.
	Location location;
	
	// For simple construction
	Symbol sym;
	Aggregate agg;
}
