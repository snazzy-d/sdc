module d.common.type;

public import d.common.builtintype;
public import d.common.qualifier;

// Because bitfields won't work with the current stringof semantic.
// It is needed to import all that instanciate TypeDescriptor.
import d.ast.type, d.ir.type;

mixin template TypeMixin(K, Payload) {
private:
	import util.bitfields;
	alias Desc = TypeDescriptor!K;

	union {
		Desc desc;
		ulong raw_desc;
	}

	Payload payload;

	static assert(K.Builtin == 0,
	              K.stringof ~ " must have a member Builtin of value 0.");
	static assert(K.Function != 0, K.stringof ~ " must have a Function kind.");

	static assert(Payload.sizeof == ulong.sizeof,
	              "Payload must be the same size as ulong.");
	static assert(is(typeof(Payload.init.next) == typeof(&this)),
	              "Payload.next must be a pointer to the next type element.");
	static assert(is(typeof(Payload.init.params) == ParamType*),
	              "Payload.params must be a pointer to parameter's types.");

	bool isPackable() const {
		return (raw_desc & (-1L << Desc.DataSize)) == 0;
	}

	auto getConstructedMixin(this T)(K k, TypeQualifier q)
			in(raw_desc != 0, "You can't construct type on None.") {
		// XXX: Consider caching in context, and stick in payload
		// instead of heap if it fit.
		return isPackable()
			? T(Desc(k, q, raw_desc), payload)
			: T(Desc(k, q), new T(desc, payload));
	}

	auto getElementMixin(this T)() {
		auto data = desc.data;
		if (data == 0) {
			assert(payload.next !is null, "None shouldn't have been packed.");
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
			foreach (i, a; args) {
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

		this(Desc d, inout Payload p) inout {
			desc = d;
			payload = p;
		}

		template PackedMixin(T...) {
			static if (T.length == 0) {
				enum PackedMixin = "";
			} else {
				enum PackedMixin = "\n@property auto " ~ T[1]
					~ "() const { return desc." ~ T[1] ~ "; }"
					~ PackedMixin!(T[3 .. $]);
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

	struct UnionTypeTpl(T, U...) {
	private:
		template TagFields(uint i, U...) {
			import std.conv;
			static if (U.length == 0) {
				enum TagFields =
					"\n\t" ~ T.stringof ~ " = " ~ to!string(i) ~ ",";
			} else {
				enum S = U[0].stringof;
				static assert((S[0] & 0x80) == 0,
				              S ~ " must not start with an unicode.");
				static assert(U[0].sizeof <= size_t.sizeof,
				              "Elements must be of pointer size or smaller.");
				import std.ascii;
				enum Name = (S == "typeof(null)")
					? "Undefined"
					: toUpper(S[0]) ~ S[1 .. $];
				enum TagFields = "\n\t" ~ Name ~ " = " ~ to!string(i) ~ ","
					~ TagFields!(i + 1, U[1 .. $]);
			}
		}

		mixin("public enum Tag {" ~ TagFields!(0, U) ~ "\n}");

		import std.traits;
		alias Tags = EnumMembers!Tag;

		// Using uint here as Tag is not accessible where the bitfield is mixed in.
		import std.typetuple;
		alias TagTuple = TypeTuple!(uint, "tag", EnumSize!Tag);

		alias Desc = TypeDescriptor!(K, TagTuple);

		union {
			Desc desc;
			ulong raw_desc;
		}

		union {
			U u;
			Payload payload;
		}

		// XXX: probably worthy of adding to phobos.
		template isImplicitelyConvertibleFrom(T) {
			import std.traits;
			enum isImplicitelyConvertibleFrom(U) =
				isImplicitlyConvertible!(T, U);
		}

		import std.typetuple, std.traits;
		enum canConstructFrom(P) =
			anySatisfy!(isImplicitelyConvertibleFrom!(Unqual!P), U);

	public:
		this(inout T t) inout {
			import std.conv;
			auto packed = t.getPackedBitfield!TagTuple(U.length.to!Tag());
			desc = packed.desc;
			payload = packed.payload;
		}

		this(P)(inout P p) inout if (canConstructFrom!P) {
			// Sanity check, in case canConstructFrom is bogous.
			bool constructed = false;

			import std.traits;
			alias UT = Unqual!P;
			foreach (E; Tags[0 .. $ - 1]) {
				static if (is(UT : U[E])) {
					Desc d;
					d.tag = E;

					// Assign d instead of setting tag to be inout compatible.
					desc = d;
					u[E] = p;

					constructed = true;
				}
			}

			assert(constructed, "canConstructFrom is bogous.");
		}

		@property
		auto tag() const {
			import std.conv;
			return desc.tag.to!Tag();
		}

		@property
		auto get(Tag E)() inout in(tag == E) {
			static if (E == U.length) {
				alias R = inout(PackedType!(T, TagTuple));
				return R(desc, payload).getType();
			} else {
				return u[E];
			}
		}
	}

	alias FunctionType = FunctionTypeTpl!(typeof(this));

	struct FunctionTypeTpl(T) {
	private:
		enum Pad = ulong.sizeof * 8 - Desc.DataSize;
		enum CountSize = ulong.sizeof * 8 - Pad - 8;

		import std.bitmanip;
		mixin(bitfields!(
			// sdfmt off
			Linkage, "lnk", 3,
			bool, "variadic", 1,
			bool, "dpure", 1,
			ulong, "ctxCount", 3,
			ulong, "paramCount", CountSize,
			uint, "", Pad, // Pad for TypeKind and qualifier
			// sdfmt on
		));

		ParamType* params;

		this(Desc desc, inout ParamType* params) inout {
			// /!\ Black magic ahead.
			auto raw_desc = cast(ulong*) &desc;

			// Remove the TypeKind and qualifier
			*raw_desc = (*raw_desc >> Pad);

			// This should point to an area of memory that have
			// the correct layout for the bitfield.
			auto f = cast(FunctionType*) raw_desc;

			// unqual trick required for bitfield
			auto unqual_this = cast(FunctionType*) &this;
			unqual_this.lnk = f.lnk;
			unqual_this.variadic = f.variadic;
			unqual_this.dpure = f.dpure;
			unqual_this.ctxCount = f.ctxCount;
			unqual_this.paramCount = f.paramCount;

			this.params = params;
		}

	public:
		this(Linkage linkage, ParamType returnType, ParamType[] params,
		     bool isVariadic) {
			lnk = linkage;
			variadic = isVariadic;
			dpure = false;
			ctxCount = 0;
			paramCount = params.length;
			this.params = (params ~ returnType).ptr;
		}

		this(Linkage linkage, ParamType returnType, ParamType ctxType,
		     ParamType[] params, bool isVariadic) {
			lnk = linkage;
			variadic = isVariadic;
			dpure = false;
			ctxCount = 1;
			paramCount = params.length;
			this.params = (ctxType ~ params ~ returnType).ptr;
		}

		T getType(TypeQualifier q = TypeQualifier.Mutable) {
			ulong d = *cast(ulong*) &this;
			auto p = Payload(cast(T*) params);
			return T(Desc(K.Function, q, d), p);
		}

		FunctionType getDelegate(ulong contextCount = 1)
				in(contextCount <= paramCount + ctxCount) {
			auto t = this;
			t.ctxCount = contextCount;
			t.paramCount = paramCount + ctxCount - contextCount;
			return t;
		}

		FunctionType getFunction() {
			return getDelegate(0);
		}

		@property
		Linkage linkage() const {
			return lnk;
		}

		auto withLinkage(Linkage linkage) inout {
			// Bypass type qualifier for params, but it's alright because
			// we do not touch any of the params and put the qualifier back.
			auto r = *(cast(FunctionType*) &this);
			r.lnk = linkage;
			return *(cast(inout(FunctionType)*) &r);
		}

		@property
		bool isVariadic() const {
			return variadic;
		}

		@property
		bool isPure() const {
			return dpure;
		}

		@property
		auto returnType() inout {
			return params[ctxCount + paramCount];
		}

		@property
		auto contexts() inout {
			return params[0 .. ctxCount];
		}

		@property
		auto parameters() inout {
			return params[ctxCount .. ctxCount + paramCount];
		}
	}

public:
	mixin TypeAccessorMixin!K;

	alias UnionType(T...) = UnionTypeTpl!(typeof(this), T);

	auto getParamType(ParamKind kind) inout {
		return getPackedBitfield!ParamTuple(kind);
	}

	auto asFunctionType() inout in(kind == K.Function, "Not a function.") {
		return inout(FunctionType)(desc, payload.params);
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
	BuiltinType builtin() inout in(kind == K.Builtin) {
		return cast(BuiltinType) desc.data;
	}
}

struct TypeDescriptor(K, T...) {
	import util.bitfields;
	enum DataSize = ulong.sizeof * 8 - 3 - EnumSize!K - SizeOfBitField!T;

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		K, "kind", EnumSize!K,
		TypeQualifier, "qualifier", 3,
		ulong, "data", DataSize,
		T,
		// sdfmt on
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
	// sdfmt off
	ParamKind, "paramKind", 2,
	// sdfmt on
);
