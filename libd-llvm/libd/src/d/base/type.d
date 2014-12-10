module d.base.type;

public import d.base.builtintype;
public import d.base.qualifier;

// Because bitfields won't work with the current stringof semantic.
// It is needed to import all that instanciate TypeDescriptor.
import d.ir.type;

mixin template TypeMixin(K, Payload) {
private:
	alias Desc = TypeDescriptor!K;
	
	union {
		Desc desc;
		ulong raw_desc;
	}
	
	Payload payload;
	
	static assert(Payload.sizeof == ulong.sizeof, "Payload must be the same size as ulong.");
	static assert(is(typeof(Payload.init.next) == typeof(&this)), "Payload.next must be a pointer to the next type element.");
	
	auto getConstructedMixin(this T)(K k, TypeQualifier q) in {
		assert(raw_desc != 0, "You can't construct type on None.");
	} body {
		// XXX: Consider caching in context, and stick in payload
		// instead of heap if it fit.
		return (raw_desc & (-1L << Desc.DataSize))
			? T(Desc(k, q), new T(desc, payload))
			: T(Desc(k, q, raw_desc), payload);
	}
	
	auto getElementMixin(this T)() {
		auto data = desc.data;
		if (data == 0) {
			assert(raw_desc != 0, "None shouldn't have been packed.");
			return *payload.next;
		}
		
		union U {
			ulong raw;
			Desc desc;
		}
		
		return T(U(data).desc, payload);
	}
	
	alias ParamType = PackedType!(typeof(this), ParamTuple);
	
	template getPackedBitfield(U...) {
		auto getPackedBitfield(A...)(A args) inout {
			import std.traits;
			alias T = Unqual!(typeof(this));
			return inout(PackedType!(T, U))(desc, args, payload);
		}
	}
	
	struct PackedType(T, U...) {
	private:
		alias BaseDesc = TypeDescriptor!K;
		alias Desc = TypeDescriptor!(K, U);
		
		union {
			Desc desc;
			ulong raw_desc;
		}
		
		Payload payload;
		
		this(A...)(BaseDesc bd, A args, inout Payload p) inout {
			union BU {
				BaseDesc base;
				ulong raw;
			}
			
			Desc d;
			foreach(i, a; args) {
				mixin("d." ~ U[3 * i + 1] ~ " = a;");
			}
			
			auto raw = BU(bd).raw;
			auto redux = raw & (-1UL >> SizeOfBitField!U);
			if (raw == redux) {
				union U {
					Desc desc;
					ulong raw;
				}
				
				raw_desc = raw | U(d).raw;
				payload = p;
			} else {
				desc = d;
				payload = inout(Payload)(new inout(T)(bd, p));
			}
		}
		
		template PackedMixin(T...) {
			static if (T.length == 0) {
				enum PackedMixin = "";
			} else {
				enum PackedMixin = "\n@property auto " ~ T[1] ~ "() const { return desc." ~ T[1] ~ "; }" ~ PackedMixin!(T[3 .. $]);
			}
		}
		
	public:
		mixin TypeAccessorMixin!K;
		mixin(PackedMixin!U);
		
		auto getType() inout {
			union BU {
				ulong raw;
				BaseDesc desc;
			}
			
			auto u = BU(raw_desc & (-1UL >> SizeOfBitField!U));
			if (u.raw == 0 && payload.next !is null) {
				return *payload.next;
			}
			
			return inout(T)(u.desc, payload);
		}
	}
	
public:
	mixin TypeAccessorMixin!K;
	
	auto getParamType(bool isRef, bool isFinal) inout {
		return getPackedBitfield!ParamTuple(isRef, isFinal);
	}
}

mixin template TypeAccessorMixin(K) {
	@property
	K kind() const {
		return desc.kind;
	}
	
	@property
	TypeQualifier qualifier() const {
		return desc.qualifier;
	}
	
	auto unqual(this T)() {
		Desc d = desc;
		d.qualifier = TypeQualifier.Mutable;
		return T(d, payload);
	}
	
	@property
	BuiltinType builtin() inout in {
		assert(kind == K.Builtin);
	} body {
		return cast(BuiltinType) desc.data;
	}
}

struct TypeDescriptor(K, T...) {
	enum DataSize = ulong.sizeof * 8 - 3 - EnumSize!K - SizeOfBitField!T;
	
	import std.bitmanip;
	mixin(bitfields!(
		K, "kind", EnumSize!K,
		TypeQualifier, "qualifier", 3,
		ulong, "data", DataSize,
		T,
	));
	
	static assert(TypeDescriptor.sizeof == ulong.sizeof);
	
	this(K k, TypeQualifier q, ulong d = 0) {
		kind = k;
		qualifier = q;
		data = d;
	}
}

import std.typetuple;
alias ParamTuple = TypeTuple!(
	bool, "isRef", 1,
	bool, "isFinal", 1,
);

template SizeOfBitField(T...) {
	static if (T.length < 2) {
		enum SizeOfBitField = 0;
	} else {
		enum SizeOfBitField = T[2] + SizeOfBitField!(T[3 .. $]);
	}
}

private:

enum EnumSize(E) = computeEnumSize!E();

size_t computeEnumSize(E)() {
	static assert(E.Builtin == 0, E.stringof ~ " must have a member Builtin of value 0.");
	
	size_t size = 0;
	
	import std.traits;
	foreach (m; EnumMembers!E) {
		size_t ms = 0;
		while ((m >> ms) != 0) {
			ms++;
		}
		
		import std.algorithm;
		size = max(size, ms);
	}
	
	return size;
}

