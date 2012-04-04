module sdc.ast.type2;

import sdc.location;
import sdc.ast.base;

class Type : Node {
	this(Location location) {
		
	}
	
	abstract Type makeConst() const;
	abstract Type makeImmutable() const;
	abstract Type makeMutable() const;
}

template isBuiltin(T) {
	import std.traits;
	
	enum bool isBuiltin = isNumeric!T || isSomeChar!T || is(T : bool) || is(Unqual!T == void);
}

template basicType(T) if(isBuiltin!T) {
	pragma(msg, T.stringof);
	
	class BasicType : Type {
		private this() {
			super(Location.init);
		}
		
		override Type makeConst() const {
			return .basicType!(const T);
		}
		
		override Type makeImmutable() const {
			return .basicType!(immutable T);
		}
		
		override Type makeMutable() const {
			import std.traits;
			return .basicType!(Unqual!T);
		}
	}
	
	immutable BasicType basicType;
	
	static this() {
		basicType = new immutable(BasicType)();
	}
}

unittest {
	void foo(T)(T t) {
	}
	
	foo(basicType!int);
	foo(basicType!void);
}

