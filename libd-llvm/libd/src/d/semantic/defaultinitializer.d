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
		})(location, t.type);
		
		e.type.qualifier = t.qualifier;
		return e;
	}
	/*
	Expression visit(Location location, BooleanType t) {
		return makeLiteral(location, false);
	}
	
	Expression visit(Location location, IntegerType t) {
		if(t.type % 2) {
			return new IntegerLiteral!true(location, 0, t);
		} else {
			return new IntegerLiteral!false(location, 0, t);
		}
	}
	
	Expression visit(Location location, FloatType t) {
		return new FloatLiteral(location, float.nan, t);
	}
	
	Expression visit(Location location, CharacterType t) {
		return new CharacterLiteral(location, [char.init], t);
	}
	*/
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

