module util.visitor;

auto dispatch(alias unhandled = function void(t) {
	import std.format;
	throw new Exception(
		format!"%s is not supported by visitor %s."(typeid(t), typeid(V)));
}, V, T, Args...)(ref V visitor, Args args, T t)
		if (is(V == struct) && (is(T == class) || is(T == interface))) {
	return dispatchImpl!unhandled(visitor, args, t);
}

auto dispatch(alias unhandled = function void(t) {
	import std.format;
	throw new Exception(
		format!"%s is not supported by visitor %s."(typeid(t), typeid(V)));
}, V, T, Args...)(V visitor, Args args, T t)
		if ((is(V == class) || is(V == interface))
			    && (is(T == class) || is(T == interface))) {
	return dispatchImpl!unhandled(visitor, args, t);
}

// XXX: is @trusted if visitor.visit is @safe .
private auto dispatchImpl(alias unhandled, V, T, Args...)(
	auto ref V visitor,
	Args args,
	T t
) in(t, "You can't dispatch null") {
	static if (is(T == class)) {
		alias o = t;
	} else {
		auto o = cast(Object) t;
	}

	auto tid = typeid(o);

	import std.traits;
	static if (is(V == struct)) {
		import std.typetuple;
		alias Members = TypeTuple!(__traits(getOverloads, V, "visit"));
	} else {
		alias Members = MemberFunctionsTuple!(V, "visit");
	}

	foreach (visit; Members) {
		alias Parameters = ParameterTypeTuple!visit;

		static if (Parameters.length == args.length + 1) {
			alias P = Parameters[args.length];

			// FIXME: ensure call is correctly done when args exists.
			static if (is(P == class) && is(P : T)
				           && !__traits(isAbstractClass, P)) {
				if (tid is typeid(P)) {
					return visitor.visit(args, () @trusted {
						// Fast cast can be trusted in this case, we already did the check.
						import util.fastcast;
						return fastCast!P(o);
					}());
				}
			}
		}
	}

	// Dispatch isn't possible.
	enum ReturnsVoid = is(typeof(return) == void);
	static if (ReturnsVoid || is(typeof(unhandled(t)) == void)) {
		unhandled(t);
		assert(ReturnsVoid);
	} else {
		return unhandled(t);
	}
}

auto accept(T, V)(T t, ref V visitor)
		if (is(V == struct) && (is(T == class) || is(T == interface))) {
	return acceptImpl(t, visitor);
}

auto accept(T, V)(T t, V visitor)
		if ((is(V == class) || is(V == interface))
			    && (is(T == class) || is(T == interface))) {
	return acceptImpl(t, visitor);
}

private auto acceptImpl(T, V)(T t, auto ref V visitor) {
	static if (is(typeof(visitor.visit(t)))) {
		return visitor.visit(t);
	} else {
		visitor.dispatch(t);
	}
}
