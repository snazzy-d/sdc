module util.visitor;

private U fastCast(U, T)(T t) if(is(T == class) && is(U == class) && is(U : T)) {
	return *(cast(U*) &t);
}

// XXX: is @trusted if visitor.visit is @safe .
auto dispatch(
	alias unhandled = function typeof(null)(t) {
		throw new Exception(typeid(t).toString() ~ " is not supported.");
		// XXX: Bugguy for some reason.
		// throw new Exception(typeid(t).toString() ~ " is not supported by visitor " ~ typeid(V).toString() ~ " .");
	}, V, T
)(ref V visitor, T t) if(is(T == class) || is(T == interface)) {
	static if(is(T == class)) {
		alias t o;
	} else {
		auto o = cast(Object) t;
	}
	
	auto tid = typeid(o);
	
	import std.traits;
	foreach (visit; MemberFunctionsTuple!(V, "visit")) {
		alias ParameterTypeTuple!visit parameters;
		
		static if(parameters.length == 1) {
			alias parameters[0] parameter;
			
			static if(is(parameter == class) && !__traits(isAbstractClass, parameter) && is(parameter : T)) {
				if(tid is typeid(parameter)) {
					return visitor.visit(fastCast!parameter(o));
				}
			}
		}
	}
	
	// Dispatch isn't possible.
	static if(is(typeof(return) == void)) {
		unhandled(t);
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

