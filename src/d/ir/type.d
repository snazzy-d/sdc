module d.ir.type;

import d.ir.error;
import d.ir.symbol;

public import d.common.builtintype;
public import d.common.qualifier;

import source.context;
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

	// Template Pattern matching for IFTI.
	Pattern,

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

	this(Desc d, inout Pattern.Payload p) inout {
		this(d, fastCast!(inout Payload)(p));
	}

	this(Desc d, inout CompileError e) inout {
		this(d, fastCast!(inout Payload)(e));
	}

	Type getConstructedType(this T)(TypeKind k, TypeQualifier q) {
		return qualify(q).getConstructedMixin(k, q);
	}

	auto acceptImpl(T)(T t) {
		final switch (kind) with (TypeKind) {
			case Builtin:
				return t.visit(builtin);

			case Struct:
				return t.visit(dstruct);

			case Class:
				return t.visit(dclass);

			case Enum:
				return t.visit(denum);

			case Alias:
				// XXX: consider how to propagate the qualifier properly.
				return t.visit(dalias);

			case Interface:
				return t.visit(dinterface);

			case Union:
				return t.visit(dunion);

			case Context:
				return t.visit(context);

			case Pointer:
				return t.visitPointerOf(element);

			case Slice:
				return t.visitSliceOf(element);

			case Array:
				return t.visitArrayOf(size, element);

			case Sequence:
				return t.visit(sequence);

			case Function:
				return t.visit(asFunctionType());

			case Pattern:
				return t.visit(pattern);

			case Error:
				return t.visit(error);
		}
	}

public:
	auto accept(T)(ref T t) if (is(T == struct)) {
		return acceptImpl(&t);
	}

	auto accept(T)(T t) if (is(T == class)) {
		return acceptImpl(t);
	}

	Type qualify(TypeQualifier q) {
		auto nq = q.add(qualifier);
		if (nq == qualifier) {
			return Type(desc, payload);
		}

		switch (kind) with (TypeKind) {
			case Builtin, Struct, Class, Enum, Alias:
			case Interface, Union, Context, Function:
			case Error:
				auto d = desc;
				d.qualifier = nq;
				return Type(d, payload);

			case Pointer:
				return element.qualify(nq).getPointer(nq);

			case Slice:
				return element.qualify(nq).getSlice(nq);

			case Array:
				return element.qualify(nq).getArray(size, nq);

			default:
				import std.format;
				assert(0, format!"%s is not implemented!"(kind));
		}
	}

	Type unqual() {
		auto d = desc;
		d.qualifier = TypeQualifier.Mutable;
		return Type(d, payload);
	}

	@property
	BuiltinType builtin() inout
			in(kind == TypeKind.Builtin, "Not a builtin type.") {
		return cast(BuiltinType) desc.data;
	}

	bool isAggregate() const {
		return (kind >= TypeKind.Struct) && (kind <= TypeKind.Union);
	}

	@property
	auto aggregate() inout in(isAggregate(), "Not an aggregate type.") {
		return payload.agg;
	}

	@property
	auto dstruct() inout in(kind == TypeKind.Struct) {
		return payload.dstruct;
	}

	@property
	auto dclass() inout in(kind == TypeKind.Class) {
		return payload.dclass;
	}

	@property
	auto denum() inout in(kind == TypeKind.Enum) {
		return payload.denum;
	}

	@property
	auto dalias() inout in(kind == TypeKind.Alias) {
		return payload.dalias;
	}

	auto getCanonical() {
		auto t = this;
		auto q = qualifier;
		while (t.kind == TypeKind.Alias) {
			// FIXME: Make sure alias is signed.
			t = t.dalias.type;
			q = q.add(t.qualifier);
		}

		return t.qualify(q);
	}

	auto getCanonicalAndPeelEnum() {
		auto t = this.getCanonical();
		auto q = qualifier;
		while (t.kind == TypeKind.Enum) {
			// FIXME: Make sure enum is signed.
			t = t.denum.type.getCanonical();
			q = q.add(t.qualifier);
		}

		return t.qualify(q);
	}

	@property
	auto dinterface() inout in(kind == TypeKind.Interface) {
		return payload.dinterface;
	}

	@property
	auto dunion() inout in(kind == TypeKind.Union) {
		return payload.dunion;
	}

	@property
	auto context() inout in(kind == TypeKind.Context) {
		return payload.context;
	}

	@property
	auto pattern() inout in(kind == TypeKind.Pattern) {
		return inout(Pattern)(desc, payload.patternPayload);
	}

	@property
	auto error() inout in(kind == TypeKind.Error) {
		return payload.error;
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
	auto element() inout
			in(hasElement, "element called on a type with no element.") {
		if (kind == TypeKind.Array) {
			return *payload.next;
		}

		return getElementMixin();
	}

	@property
	uint size() const in(kind == TypeKind.Array, "Only array have size.") {
		assert(desc.data <= uint.max);
		return cast(uint) desc.data;
	}

	@property
	auto sequence() inout
			in(kind == TypeKind.Sequence, "Not a sequence type.") {
		return payload.next[0 .. desc.data];
	}

	bool hasPointerABI() const {
		switch (kind) with (TypeKind) {
			case Class, Pointer:
				return true;

			case Alias:
				return dalias.type.hasPointerABI();

			case Function:
				return asFunctionType().contexts.length == 0;

			default:
				return false;
		}
	}

	bool hasIndirection() {
		auto t = getCanonicalAndPeelEnum();
		final switch (t.kind) with (TypeKind) {
			case Builtin:
				// Is this, really ?
				return t.builtin == BuiltinType.Null;

			case Alias, Enum, Pattern, Error:
				assert(0);

			case Pointer, Slice, Class, Interface, Context:
				return true;

			case Array:
				return element.hasIndirection;

			case Struct:
				return t.dstruct.hasIndirection;

			case Union:
				return t.dunion.hasIndirection;

			case Function:
				import std.algorithm;
				return asFunctionType()
					.contexts.any!(t => t.isRef || t.getType().hasIndirection);

			case Sequence:
				import std.algorithm;
				return sequence.any!(t => t.hasIndirection);
		}
	}

	string toString(const Context c,
	                TypeQualifier q = TypeQualifier.Mutable) const {
		auto s = toUnqualString(c);
		if (q == qualifier) {
			return s;
		}

		final switch (qualifier) with (TypeQualifier) {
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

	string toUnqualString(const Context c) const {
		final switch (kind) with (TypeKind) {
			case Builtin:
				import d.common.builtintype : toString;
				return toString(builtin);

			case Struct:
				return dstruct.name.toString(c);

			case Class:
				return dclass.name.toString(c);

			case Enum:
				return denum.name.toString(c);

			case Alias:
				return dalias.name.toString(c);

			case Interface:
				return dinterface.name.toString(c);

			case Union:
				return dunion.name.toString(c);

			case Context:
				return "__ctx";

			case Pointer:
				return element.toString(c, qualifier) ~ "*";

			case Slice:
				return element.toString(c, qualifier) ~ "[]";

			case Array:
				import std.conv;
				return element.toString(c, qualifier) ~ "[" ~ to!string(size)
					~ "]";

			case Sequence:
				import std.algorithm, std.range;
				// XXX: need to use this because of identifier hijacking in the import.
				return "(" ~ this.sequence.map!(e => e.toString(c, qualifier))
				                 .join(", ") ~ ")";

			case Function:
				auto f = asFunctionType();

				auto linkage = "";
				if (f.linkage != Linkage.D) {
					import std.conv;
					linkage = "extern(" ~ f.linkage.to!string() ~ ") ";
				}

				auto ret = f.returnType.toString(c);
				auto base = f.contexts.length ? " delegate(" : " function(";
				import std.algorithm, std.range;
				auto args = f.parameters.map!(p => p.toString(c)).join(", ");
				return linkage ~ ret ~ base ~ args
					~ (f.isVariadic ? ", ...)" : ")");

			case Pattern:
				return pattern.toString(c);

			case Error:
				return "__error__(" ~ error.toString(c) ~ ")";
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
		return Pattern(p).getType(q);
	}

	Type getContextType(Function f, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Context, q), f);
	}

	Type get(CompileError e, TypeQualifier q = TypeQualifier.Mutable) {
		return Type(Desc(TypeKind.Error, q), e);
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
	foreach (_; 0 .. 64) {
		t = t.getPointer().getSlice();
	}

	foreach (_; 0 .. 64) {
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
	import source.location, source.name, d.ir.symbol;
	auto m = new Module(Location.init, BuiltinName!"", null);
	auto c = new Class(Location.init, m, BuiltinName!"");
	auto tc = Type.get(c);
	assert(tc.isAggregate());
	assert(tc.aggregate is c);

	auto cc = Type.get(c, TypeQualifier.Const);
	auto csc = tc.getSlice(TypeQualifier.Const);
	assert(cc == csc.element);
}

unittest {
	import source.location, source.name, d.ir.symbol;
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
	import source.location, source.name, d.ir.symbol;
	auto f = Type.get(BuiltinType.Float, TypeQualifier.Const);
	auto a = new TypeAlias(Location.init, BuiltinName!"", f);

	auto m = new Module(Location.init, BuiltinName!"", null);
	auto e1 = new Enum(Location.init, m, BuiltinName!"", Type.get(a), []);
	auto e1t = Type.get(e1);
	assert(e1t.getCanonicalAndPeelEnum() == f);

	auto e2 = new Enum(Location.init, m, BuiltinName!"", e1t, []);
	auto e2t = Type.get(e2, TypeQualifier.Immutable);
	assert(e2t.getCanonicalAndPeelEnum() == f.qualify(TypeQualifier.Immutable));

	auto e3 = new Enum(Location.init, m, BuiltinName!"", e2t, []);
	auto e3t = Type.get(e3, TypeQualifier.Const);
	assert(e3t.getCanonicalAndPeelEnum() == f.qualify(TypeQualifier.Immutable));
}

alias ParamType = Type.ParamType;

string toString(const ParamType t, const Context c) {
	string s;
	final switch (t.paramKind) with (ParamKind) {
		case Regular:
			s = "";
			break;

		case Final:
			s = "final ";
			break;

		case Ref:
			s = "ref ";
			break;
	}

	return s ~ t.getType().toString(c);
}

inout(ParamType) getParamType(inout ParamType t, ParamKind kind) {
	return t.getType().getParamType(kind);
}

@property
bool isRef(const ParamType t) {
	return t.paramKind == ParamKind.Ref;
}

@property
bool isFinal(const ParamType t) {
	return t.paramKind == ParamKind.Final;
}

unittest {
	auto pi = Type.get(BuiltinType.Int).getPointer(TypeQualifier.Const);
	auto p = pi.getParamType(ParamKind.Ref);

	assert(p.paramKind == ParamKind.Ref);
	assert(p.qualifier == TypeQualifier.Const);

	auto pt = p.getType();
	assert(pt == pi);
}

alias FunctionType = Type.FunctionType;

unittest {
	auto r =
		Type.get(BuiltinType.Void).getPointer().getParamType(ParamKind.Regular);
	auto c =
		Type.get(BuiltinType.Null).getSlice().getParamType(ParamKind.Final);
	auto p = Type.get(BuiltinType.Float).getSlice(TypeQualifier.Immutable)
	             .getParamType(ParamKind.Ref);
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
	assert(d2.getFunction() == f);
}

// Facility for IFTI pattern matching.
enum PatternKind : ubyte {
	Parameter,
	Instance,
	TypeBracketValue,
	TypeBracketType,
}

struct Pattern {
private:
	alias Desc = Type.Desc;

	import util.bitfields;
	enum KindSize = EnumSize!PatternKind;
	enum Pad = ulong.sizeof * 8 - Type.Desc.DataSize;
	enum CountSize = ulong.sizeof * 8 - KindSize - Pad;

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		PatternKind, "kind", KindSize,
		ulong, "argCount", CountSize,
		uint, "", Pad, // Pad for TypeKind and qualifier
		// sdfmt on
	));

	union Payload {
		TypeTemplateParameter param;
		TypeValuePair* typeValuePair;
		TemplateArgument* args;
	}

	Payload payload;

	static assert(Payload.sizeof == ulong.sizeof,
	              "Payload must be the same size as ulong.");

	this(Desc desc, inout Payload payload) inout {
		// /!\ Black magic ahead.
		auto raw_desc = cast(ulong*) &desc;

		// Remove the TypeKind and qualifier
		*raw_desc = (*raw_desc >> Pad);

		// This should point to an area of memory that have
		// the correct layout for the bitfield.
		auto p = cast(Pattern*) raw_desc;

		// unqual trick required for bitfield
		auto unqual_this = cast(Pattern*) &this;
		unqual_this.kind = p.kind;
		unqual_this.argCount = p.argCount;

		this.payload = payload;
	}

	this(PatternKind k, ulong c, Payload p) {
		kind = k;
		argCount = c;
		payload = p;
	}

	struct TypeValuePair {
		Type type;
		ValueTemplateParameter value;
	}

	auto getTypeValuePair() inout in(kind == PatternKind.TypeBracketValue) {
		return payload.typeValuePair;
	}

	struct Instantiation {
		Symbol instantiated;
		TemplateArgument[] args;
	}

	auto getInstatiation() inout in(kind == PatternKind.Instance) {
		auto c = argCount;
		return inout(Instantiation)(
			payload.args[c].get!(TemplateArgument.Tag.Symbol),
			payload.args[0 .. c]
		);
	}

public:
	import util.fastcast;
	this(TypeTemplateParameter p) {
		this(PatternKind.Parameter, 0, fastCast!Payload(p));
	}

	this(Type t, ValueTemplateParameter v) {
		auto p = new TypeValuePair(t, v);
		this(PatternKind.TypeBracketValue, 0, fastCast!Payload(p));
	}

	this(Symbol instantiated, TemplateArgument[] args) {
		args ~= TemplateArgument(instantiated);
		this(PatternKind.Instance, args.length - 1, fastCast!Payload(args.ptr));
	}

	@property
	auto parameter() inout in(kind == PatternKind.Parameter) {
		return payload.param;
	}

	Type getType(TypeQualifier q = TypeQualifier.Mutable) {
		ulong d = *cast(ulong*) &this;
		return Type(Desc(TypeKind.Pattern, q, d), payload);
	}

	auto accept(T)(ref T t) if (is(T == struct)) {
		return acceptImpl(&t);
	}

	auto accept(T)(T t) if (is(T == class)) {
		return acceptImpl(t);
	}

	string toString(const Context c) const {
		final switch (kind) with (PatternKind) {
			case Parameter:
				return parameter.name.toString(c);

			case Instance:
				assert(0, "Not implemented");

			case TypeBracketValue:
				auto p = getTypeValuePair();
				return p.type.toString(c) ~ '[' ~ p.value.name.toString(c)
					~ ']';

			case TypeBracketType:
				assert(0, "Not implemented");
		}
	}

private:
	auto acceptImpl(T)(T t) {
		final switch (kind) with (PatternKind) {
			case Parameter:
				return t.visit(parameter);

			case Instance:
				auto i = getInstatiation();
				return t.visit(i.instantiated, i.args);

			case TypeBracketValue:
				auto p = getTypeValuePair();
				return t.visit(p.type, p.value);

			case TypeBracketType:
				assert(0, "Not implemented");
		}
	}
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
	Pattern.Payload patternPayload;

	// For speculative compilation.
	CompileError error;

	// For simple construction
	Symbol sym;
	Aggregate agg;
}
