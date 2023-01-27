module d.ast.type;

public import d.common.builtintype;
public import d.common.qualifier;

import source.context;
import d.common.type;

enum AstTypeKind : ubyte {
	Builtin,
	Identifier,

	// Type constructors
	Pointer,
	Slice,
	Array,
	Map,
	Bracket,
	Function,

	// typeof
	TypeOf,
}

struct AstType {
private:
	mixin TypeMixin!(AstTypeKind, Payload);

	this(Desc d, inout Payload p = Payload.init) inout {
		desc = d;
		payload = p;
	}

	import util.fastcast;
	this(Desc d, inout Identifier i) inout {
		this(d, fastCast!(inout Payload)(i));
	}

	this(Desc d, inout AstExpression e) inout {
		this(d, fastCast!(inout Payload)(e));
	}

	this(Desc d, inout ArrayPayload* a) inout {
		this(d, fastCast!(inout Payload)(a));
	}

	this(Desc d, inout MapPayload* m) inout {
		this(d, fastCast!(inout Payload)(m));
	}

	this(Desc d, inout BracketPayload* b) inout {
		this(d, fastCast!(inout Payload)(b));
	}

	this(Desc d, inout AstType* t) inout {
		this(d, fastCast!(inout Payload)(t));
	}

	AstType getConstructedType(this T)(AstTypeKind k, TypeQualifier q)
			in(!isAuto, "Cannot build on top of auto type.") {
		return getConstructedMixin(k, q);
	}

	auto acceptImpl(T)(T t) {
		final switch (kind) with (AstTypeKind) {
			case Builtin:
				return t.visit(builtin);

			case Identifier:
				return t.visit(identifier);

			case Pointer:
				return t.visitPointerOf(element);

			case Slice:
				return t.visitSliceOf(element);

			case Array:
				return t.visitArrayOf(size, element);

			case Map:
				return t.visitMapOf(key, element);

			case Bracket:
				return t.visitBracketOf(ikey, element);

			case Function:
				return t.visit(asFunctionType());

			case TypeOf:
				return desc.data ? t.visitTypeOfReturn() : t.visit(expression);
		}
	}

public:
	auto accept(T)(ref T t) if (is(T == struct)) {
		return acceptImpl(&t);
	}

	auto accept(T)(T t) if (is(T == class)) {
		return acceptImpl(t);
	}

	AstType qualify(TypeQualifier q) {
		auto d = desc;
		d.qualifier = q.add(qualifier);
		return AstType(d, payload);
	}

	AstType unqual() {
		auto d = desc;
		d.qualifier = TypeQualifier.Mutable;
		return AstType(d, payload);
	}

	@property
	BuiltinType builtin() inout in(kind == AstTypeKind.Builtin) {
		return cast(BuiltinType) desc.data;
	}

	@property
	bool isAuto() inout {
		return payload.next is null && kind == AstTypeKind.Builtin
			&& builtin == BuiltinType.None;
	}

	@property
	auto identifier() inout in(kind == AstTypeKind.Identifier) {
		return payload.identifier;
	}

	AstType getPointer(TypeQualifier q = TypeQualifier.Mutable) {
		return getConstructedType(AstTypeKind.Pointer, q);
	}

	AstType getSlice(TypeQualifier q = TypeQualifier.Mutable) {
		return getConstructedType(AstTypeKind.Slice, q);
	}

	AstType getArray(
		AstExpression size,
		TypeQualifier q = TypeQualifier.Mutable
	) in(!isAuto, "Cannot build on top of auto type.") {
		return (payload.next is null && isPackable())
			? AstType(Desc(AstTypeKind.Array, q, raw_desc), size)
			: AstType(Desc(AstTypeKind.Array, q), new ArrayPayload(size, this));
	}

	AstType getMap(AstType key, TypeQualifier q = TypeQualifier.Mutable)
			in(!isAuto, "Cannot build on top of auto type.") {
		return AstType(Desc(AstTypeKind.Map, q), new MapPayload(key, this));
	}

	AstType getBracket(Identifier ikey, TypeQualifier q = TypeQualifier.Mutable)
			in(!isAuto, "Cannot build on top of auto type.") {
		return (payload.next is null && isPackable())
			? AstType(Desc(AstTypeKind.Bracket, q, raw_desc), ikey)
			: AstType(Desc(AstTypeKind.Bracket, q),
			          new BracketPayload(ikey, this));
	}

	bool hasElement() const {
		return (kind >= AstTypeKind.Pointer) && (kind <= AstTypeKind.Bracket);
	}

	@property
	auto element() inout
			in(hasElement, "element called on a type with no element.") {
		if (kind < AstTypeKind.Array) {
			return getElementMixin();
		}

		switch (kind) with (AstTypeKind) {
			case Array:
				return desc.data
					? inout(AstType)(getElementMixin().desc)
					: payload.array.type;

			case Map:
				return payload.map.type;

			case Bracket:
				return desc.data
					? inout(AstType)(getElementMixin().desc)
					: payload.bracket.type;

			default:
				assert(0);
		}
	}

	@property
	auto size() inout in(kind == AstTypeKind.Array, "Only array have size.") {
		return desc.data ? payload.expr : payload.array.size;
	}

	@property
	auto key() inout in(kind == AstTypeKind.Map, "Only maps have key.") {
		return payload.map.key;
	}

	@property
	auto ikey() inout in(kind == AstTypeKind.Bracket,
	                     "Only bracket[identifier] have ikey.") {
		return desc.data ? payload.identifier : payload.bracket.key;
	}

	@property
	auto expression() inout in(kind == AstTypeKind.TypeOf && desc.data == 0) {
		return payload.expr;
	}

	@property
	bool isTypeOfReturn() inout {
		return kind == AstTypeKind.TypeOf && desc.data != 0;
	}

	string toString(const Context c) const {
		auto s = toUnqualString(c);

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
		final switch (kind) with (AstTypeKind) {
			case Builtin:
				import d.common.builtintype : toString;
				return toString(builtin);

			case Identifier:
				return identifier.toString(c);

			case Pointer:
				return element.toString(c) ~ "*";

			case Slice:
				return element.toString(c) ~ "[]";

			case Array:
				return element.toString(c) ~ "[" ~ size.toString(c) ~ "]";

			case Map:
				return element.toString(c) ~ "[" ~ key.toString(c) ~ "]";

			case Bracket:
				return element.toString(c) ~ "[" ~ ikey.toString(c) ~ "]";

			case Function:
				auto f = asFunctionType();
				auto ret = f.returnType.toString(c);
				auto base = f.contexts.length ? " delegate(" : " function(";
				import std.algorithm, std.range;
				auto args = f.parameters.map!(p => p.toString(c)).join(", ");
				return ret ~ base ~ args ~ (f.isVariadic ? ", ...)" : ")");

			case TypeOf:
				return desc.data
					? "typeof(return)"
					: "typeof(" ~ expression.toString(c) ~ ")";
		}
	}

static:
	AstType get(BuiltinType bt, TypeQualifier q = TypeQualifier.Mutable) {
		Payload p; // Needed because of lolbug in inout
		return AstType(Desc(AstTypeKind.Builtin, q, bt), p);
	}

	AstType getAuto(TypeQualifier q = TypeQualifier.Mutable) {
		return get(BuiltinType.None, q);
	}

	AstType get(Identifier i, TypeQualifier q = TypeQualifier.Mutable) {
		return AstType(Desc(AstTypeKind.Identifier, q), i);
	}

	AstType getTypeOf(AstExpression e,
	                  TypeQualifier q = TypeQualifier.Mutable) {
		return AstType(Desc(AstTypeKind.TypeOf, q), e);
	}

	AstType getTypeOfReturn(TypeQualifier q = TypeQualifier.Mutable) {
		Payload p; // Needed because of lolbug in inout
		return AstType(Desc(AstTypeKind.TypeOf, q, 1), p);
	}
}

unittest {
	AstType t;
	assert(t.isAuto);
	assert(t.qualifier == TypeQualifier.Mutable);

	t = t.qualify(TypeQualifier.Immutable);
	assert(t.isAuto);
	assert(t.qualifier == TypeQualifier.Immutable);

	t = AstType.getAuto(TypeQualifier.Const);
	assert(t.isAuto);
	assert(t.qualifier == TypeQualifier.Const);

	auto l = AstType.get(BuiltinType.Long);
	auto p = l.getPointer();
	assert(p.element == l);

	import source.location;
	auto s1 = new DollarExpression(Location.init);
	auto a1 = l.getArray(s1);
	assert(a1.size is s1);
	assert(a1.element == l);

	auto s2 = new DollarExpression(Location.init);
	auto a2 = a1.getArray(s2);
	assert(a2.size is s2);
	assert(a2.element == a1);

	auto f = AstType.get(BuiltinType.Float);
	auto m = l.getMap(f);
	assert(m.key == f);
	assert(m.element == l);

	import source.name;
	auto i = new BasicIdentifier(Location.init, BuiltinName!"");
	t = AstType.get(i, TypeQualifier.Shared);
	assert(t.identifier is i);
	assert(t.qualifier is TypeQualifier.Shared);

	auto b1 = l.getBracket(i);
	assert(b1.ikey is i);
	assert(b1.element == l);

	auto b2 = b1.getBracket(i);
	assert(b2.ikey is i);
	assert(b2.element == b1);

	auto e = new DollarExpression(Location.init);
	t = AstType.getTypeOf(e);
	assert(t.expression is e);

	t = AstType.getTypeOfReturn();

	import source.context;
	Context c;
	assert(t.toString(c) == "typeof(return)");
}

alias ParamAstType = AstType.ParamType;

string toString(const ParamAstType t, const Context c) {
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

inout(ParamAstType) getParamType(inout ParamAstType t, ParamKind kind) {
	return t.getType().getParamType(kind);
}

alias FunctionAstType = AstType.FunctionType;

private:

// XXX: we put it as a UFCS property to avoid forward reference.
@property
inout(ParamAstType)* params(inout Payload p) {
	import util.fastcast;
	return cast(inout ParamAstType*) p.next;
}

import d.ast.expression;
import d.ast.identifier;

union Payload {
	AstType* next;

	Identifier identifier;

	ArrayPayload* array;
	MapPayload* map;
	BracketPayload* bracket;

	AstExpression expr;
}

struct ArrayPayload {
	AstExpression size;
	AstType type;
}

struct MapPayload {
	AstType key;
	AstType type;
}

struct BracketPayload {
	Identifier key;
	AstType type;
}
