module util.visitor;

@trusted
private U fastCast(U, T)(T t) if(is(T == class) && is(U == class) && is(U : T)) in {
	assert(cast(U) t);
} body {
	return *(cast(U*) &t);
}

// XXX: is @trusted if visitor.visit is @safe .
auto dispatch(
	alias unhandled = function void(t) {
		throw new Exception(typeid(t).toString() ~ " is not supported.");
		// XXX: Bugguy for some reason.
		// throw new Exception(typeid(t).toString() ~ " is not supported by visitor " ~ typeid(V).toString() ~ " .");
	}, V, T, Args...
)(ref V visitor, Args args, T t) if(is(T == class) || is(T == interface)) in {
	assert(t, "You can't dispatch null");
} body {
	static if(is(T == class)) {
		alias t o;
	} else {
		auto o = cast(Object) t;
	}
	
	auto tid = typeid(o);
	
	import std.traits;
	foreach(visit; MemberFunctionsTuple!(V, "visit")) {
		alias ParameterTypeTuple!visit parameters;
		
		static if(parameters.length == args.length + 1) {
			alias parameters[args.length] parameter;
			
			// FIXME: ensure call is correctly done when args exists.
			static if(is(parameter == class) && !__traits(isAbstractClass, parameter) && is(parameter : T)) {
				if(tid is typeid(parameter)) {
					return visitor.visit(args, fastCast!parameter(o));
				}
			}
		}
	}
	
	// Dispatch isn't possible.
	enum returnVoid = is(typeof(return) == void);
	static if(returnVoid || is(typeof(unhandled(t)) == void)) {
		unhandled(t);
		assert(returnVoid);
	} else {
		return unhandled(t);
	}
}

auto accept(T, V)(T t, ref V visitor) if(is(T == class) || is(T == interface)) {
	static if(is(typeof(visitor.visit(t)))) {
		return visitor.visit(t);
	} else {
		visitor.dispatch(t);
	}
}

