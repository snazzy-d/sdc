module sdc.ast.type2;

import sdc.location;
import sdc.ast.base;

class Type : Node {
	this(Location location) {
		
	}
}

template isBuiltin(T) {
	import std.traits;
	
	enum bool isBuiltin = isNumeric!T || isSomeChar!T || is(T : bool) || is(T == void);
}

template builtinType(T) if(isBuiltin!T) {
	class BuiltinType : Type {
		private this() {
			super(Location.init);
		}
	}
	
	immutable BuiltinType builtinType;
	
	static this() {
		builtinType = new immutable(BuiltinType)();
	}
}

unittest {
	void foo(T)(T t) {
		pragma(msg, T.stringof);
	}
	
	foo(builtinType!int);
	foo(builtinType!void);
}

