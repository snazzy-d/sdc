module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.type;

import d.location;

final class DefaultInitializerVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Expression visit(Location location, QualType t) {
		auto e = this.dispatch!((t) {
			return pass.raiseCondition!Expression(location, "Type " ~ typeid(t).toString() ~ " has no initializer.");
		})(location, t.type.canonical);
		
		e.type.qualifier = t.qualifier;
		return e;
	}
	
	Expression visit(Location location, BuiltinType t) {
		final switch(t.kind) with(TypeKind) {
			case None :
			case Void :
				assert(0, "Not Implemented");
			
			case Bool :
				return new BooleanLiteral(location, false);
			
			case Char :
			case Wchar :
			case Dchar :
				return new CharacterLiteral(location, [char.init], t.kind);
			
			case Ubyte :
			case Ushort :
			case Uint :
			case Ulong :
			case Ucent :
				return new IntegerLiteral!false(location, 0, t.kind);
			
			case Byte :
			case Short :
			case Int :
			case Long :
			case Cent :
				return new IntegerLiteral!true(location, 0, t.kind);
			
			case Float :
			case Double :
			case Real :
				return new FloatLiteral(location, float.nan, t.kind);
			
			case Null :
				return new NullLiteral(location);
		}
	}
	
	Expression visit(Location location, PointerType t) {
		return new NullLiteral(location);
	}
	/*
	Expression visit(SliceType t) {
		// Convoluted way to create the array due to compiler limitations.
		Expression[] init = [new NullLiteral(location, t.type)];
		init ~= makeLiteral(location, 0UL);
		
		auto ret = new TupleExpression(location, init);
		ret.type = t;
		
		return ret;
	}
	*/
	/*
	Expression visit(Location location, ArrayType t) {
		return new VoidInitializer(location, t);
	}
	*/
	Expression visit(Location location, StructType t) {
		auto s = t.dstruct;
		scheduler.require(s, Step.Populated);
		
		import d.ir.symbol;
		auto init = cast(Variable) s.dscope.resolve("init");
		
		// XXX: Create a new node ?
		return init.value;
	}
	
	Expression visit(Location location, ClassType t) {
		return new NullLiteral(location);
	}
	
	Expression visit(Location location, FunctionType t) {
		return new NullLiteral(location);
	}
}

