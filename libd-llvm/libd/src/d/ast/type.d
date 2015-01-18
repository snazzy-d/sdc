module d.ast.type;

public import d.base.builtintype;
public import d.base.qualifier;

import d.base.type;

import d.context;

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
	
	AstType getConstructedType(this T)(AstTypeKind k, TypeQualifier q) in {
		assert(!isAuto, "Cannot build on top of auto type.");
	} body {
		return getConstructedMixin(k, q);
	}
	
	auto acceptImpl(T)(T t) {
		final switch(kind) with(AstTypeKind) {
			case Builtin :
				return t.visit(builtin);
			
			case Identifier :
				return t.visit(identifier);
			
			case Pointer :
				return t.visitPointerOf(element);
			
			case Slice :
				return t.visitSliceOf(element);
			
			case Array :
				return t.visitArrayOf(size, element);
			
			case Map :
				return t.visitMapOf(key, element);
			
			case Bracket :
				return t.visitBracketOf(ikey, element);
			
			case Function :
				return t.visit(asFunctionType());
			
			case TypeOf :
				return t.visit(expression);
		}
	}
	
public:
	auto accept(T)(ref T t) if(is(T == struct)) {
		return acceptImpl(&t);
	}
	
	auto accept(T)(T t) if(is(T == class)) {
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
	BuiltinType builtin() inout in {
		assert(kind == AstTypeKind.Builtin);
	} body {
		return cast(BuiltinType) desc.data;
	}
	
	@property
	bool isAuto() inout {
		return payload.next is null && kind == AstTypeKind.Builtin && builtin == BuiltinType.None;
	}
	
	@property
	auto identifier() inout in {
		assert(kind == AstTypeKind.Identifier);
	} body {
		return payload.identifier;
	}
	
	@property
	auto expression() inout in {
		assert(kind == AstTypeKind.TypeOf);
	} body {
		return payload.expr;
	}
	
	AstType getPointer(TypeQualifier q = TypeQualifier.Mutable) {
		return getConstructedType(AstTypeKind.Pointer, q);
	}
	
	AstType getSlice(TypeQualifier q = TypeQualifier.Mutable) {
		return getConstructedType(AstTypeKind.Slice, q);
	}
	
	AstType getArray(AstExpression size, TypeQualifier q = TypeQualifier.Mutable) {
		return AstType(Desc(AstTypeKind.Array, q), new ArrayPayload(this, size));
	}
	
	AstType getMap(AstType key, TypeQualifier q = TypeQualifier.Mutable) {
		return AstType(Desc(AstTypeKind.Map, q), new MapPayload(this, key));
	}
	
	AstType getBracket(Identifier ikey, TypeQualifier q = TypeQualifier.Mutable) {
		return AstType(Desc(AstTypeKind.Bracket, q), new BracketPayload(this, ikey));
	}
	
	bool hasElement() const {
		return (kind >= AstTypeKind.Pointer) && (kind <= AstTypeKind.Bracket);
	}
	
	@property
	auto element() inout in {
		assert(hasElement, "element called on a type with no element.");
	} body {
		if (kind >= AstTypeKind.Array) {
			return payload.array.type;
		}
		
		return getElementMixin();
	}
	
	@property
	auto size() inout in {
		assert(kind == AstTypeKind.Array, "Only array have size.");
	} body {
		return payload.array.size;
	}
	
	@property
	auto key() inout in {
		assert(kind == AstTypeKind.Map, "Only maps have key.");
	} body {
		return payload.map.key;
	}
	
	@property
	auto ikey() inout in {
		assert(kind == AstTypeKind.Bracket, "Only bracket[identifier] have ikey.");
	} body {
		return payload.bracket.key;
	}
	
	string toString(Context c) const {
		auto s = toUnqualString(c);
		
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
	
	string toUnqualString(Context c) const {
		final switch(kind) with(AstTypeKind) {
			case Builtin :
				import d.base.builtintype : toString;
				return toString(builtin);
			
			case Identifier :
				return identifier.toString(c);
			
			case Pointer :
				return element.toString(c) ~ "*";
			
			case Slice :
				return element.toString(c) ~ "[]";
			
			case Array :
				return element.toString(c) ~ "[" ~ size.toString(c) ~ "]";
			
			case Map :
				return element.toString(c) ~ "[" ~ key.toString(c) ~ "]";
			
			case Bracket :
				return element.toString(c) ~ "[" ~ ikey.toString(c) ~ "]";
			
			case Function :
				auto f = asFunctionType();
				auto ret = f.returnType.toString(c);
				auto base = f.contexts.length ? " delegate(" : " function(";
				import std.algorithm, std.range;
				auto args = f.parameters.map!(p => p.toString(c)).join(", ");
				return ret ~ base ~ args ~ (f.isVariadic ? ", ...)" : ")");
			
			case TypeOf :
				return "typeof(" ~ expression.toString(c) ~ ")";
		}
	}
	
static:
	AstType get(BuiltinType bt, TypeQualifier q = TypeQualifier.Mutable) {
		Payload p;
		return AstType(Desc(AstTypeKind.Builtin, q, bt), p);
	}
	
	AstType getAuto(TypeQualifier q = TypeQualifier.Mutable) {
		return get(BuiltinType.None, q);
	}
	
	AstType get(Identifier i, TypeQualifier q = TypeQualifier.Mutable) {
		return AstType(Desc(AstTypeKind.Identifier, q), i);
	}
	
	AstType get(AstExpression e, TypeQualifier q = TypeQualifier.Mutable) {
		return AstType(Desc(AstTypeKind.TypeOf, q), e);
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
	
	import d.location;
	auto s = new DollarExpression(Location.init);
	auto a = l.getArray(s);
	assert(a.size is s);
	assert(a.element == l);
	
	auto f = AstType.get(BuiltinType.Float);
	auto m = l.getMap(f);
	assert(m.key == f);
	assert(m.element == l);
	
	auto i = new BasicIdentifier(Location.init, BuiltinName!"");
	t = AstType.get(i, TypeQualifier.Shared);
	assert(t.identifier is i);
	assert(t.qualifier is TypeQualifier.Shared);
	
	auto b = l.getBracket(i);
	assert(b.ikey is i);
	assert(b.element == l);
}

alias ParamAstType = AstType.ParamType;

string toString(const ParamAstType t, Context c) {
	string s;
	if (t.isRef && t.isFinal) {
		s = "final ref ";
	} else if (t.isRef) {
		s = "ref ";
	} else if (t.isFinal) {
		s = "final ";
	}
	
	return s ~ t.getType().toString(c);
}

inout(ParamAstType) getParamType(inout ParamAstType t, bool isRef, bool isFinal) {
	return t.getType().getParamType(isRef, isFinal);
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
	AstType type;
	AstExpression size;
}

struct MapPayload {
	AstType type;
	AstType key;
}

struct BracketPayload {
	AstType type;
	Identifier key;
}

