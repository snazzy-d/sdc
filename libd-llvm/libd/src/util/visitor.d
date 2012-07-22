module util.visitor;

import std.traits;

private U fastCast(U, T)(ref T t) if(is(T == class) && is(U : T)) {
	return *(cast(U*) &t);
}

@trusted
void dispatch(
	alias unhandled = (t){
		throw new Exception(typeid(t).toString() ~ " is not supported.");
	}, V, T
)(ref V visitor, ref T t) if(is(T == class)) {
	auto tid = typeid(t);
	
	import std.traits;
	foreach (visit; MemberFunctionsTuple!(V, "visit")) {
		alias ParameterTypeTuple!visit parameters;
		
		static if(parameters.length == 1) {
			alias parameters[0] parameter;
			
			static if(!__traits(isAbstractClass, parameter) && is(parameter : T)) {
				if(tid is typeid(parameter)) {
					visitor.visit(fastCast!parameter(t));
					return;
				}
			}
		}
	}
	
	unhandled(t);
}

auto accept(T, V)(ref T t, ref V visitor) {
	static if(is(typeof(visitor.visit(t)))) {
		return visitor.visit(t);
	} else {
		visitor.dispatch(t);
	}
}

