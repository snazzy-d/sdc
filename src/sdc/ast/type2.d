module sdc.ast.type2;

import sdc.location;
import sdc.ast.base : Node;
import sdc.ast.expression2;
import sdc.ast.identifier2;

class Type : Node, Namespace {
	this(Location location) {
		this.location = location;
	}
	
	abstract Type makeMutable();
	
	abstract Type makeImmutable();
	
	abstract Type makeConst();
	
	abstract Type makeInout();
}

class SimpleStorageClassType : Type {
	private uint storageClass = 0;
	
	enum MUTABLE = 0x00;
	enum IMMUTABLE = 0x01;
	enum CONST = 0x02;
	enum INOUT = 0x03;
	
	enum MASK = ~0x03;
	
	this(Location location) {
		super(location);
	}
	
final:	// Check whenever these operation make sense.
	override Type makeMutable() {
		storageClass &= MASK;
		return this;
	}
	
	override Type makeImmutable() {
		makeMutable();
		storageClass |= IMMUTABLE;
		return this;
	}
	
	override Type makeConst() {
		makeMutable();
		storageClass |= CONST;
		return this;
	}
	
	override Type makeInout() {
		makeMutable();
		storageClass |= INOUT;
		return this;
	}
}

template isBuiltin(T) {
	import std.traits;
	
	enum bool isBuiltin = isNumeric!T || isSomeChar!T || is(Unqual!T == bool) || is(Unqual!T == void);
}

/**
 * All basics types and qualified basic types.
 */
template basicType(T) if(isBuiltin!T) {
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
		
		override Type makeInout() const {
			return .basicType!(inout T);
		}
	}
	
	immutable BasicType basicType;
	
	static this() {
		basicType = new immutable(BasicType)();
	}
}

/**
 * Type defined by an identifier
 */
class IdentifierType : SimpleStorageClassType {
	private Identifier identifier;
	
	this(Location location, Identifier identifier) {
		super(location);
		
		this.identifier = identifier;
	}
}


/**
 * Type defined by typeof(Expression)
 */
class TypeofType : SimpleStorageClassType {
	private Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
}

/**
 * Type defined by typeof(return)
 */
class ReturnType : SimpleStorageClassType {
	this(Location location) {
		super(location);
	}
}

