module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.location;

final class DefaultInitializerVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Expression visit(Location location, Type t) out(result) {
		assert(result.type);
	} body {
		return this.dispatch!(delegate Expression(Type t) {
			return pass.raiseCondition!Expression(location, "Type " ~ typeid(t).toString() ~ " has no initializer.");
		})(location, t);
	}
	
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
	
	Expression visit(Location location, PointerType t) {
		return new NullLiteral(location, t);
	}
	
	Expression visit(Location location, FunctionType t) {
		return new NullLiteral(location, t);
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
	Expression visit(Location location, StaticArrayType t) {
		return new VoidInitializer(location, t);
	}
	
	Expression visit(Location location, SymbolType t) {
		return this.dispatch(location, scheduler.require(t.symbol));
	}
	
	Expression visit(Location location, StructDefinition d) {
		d = cast(StructDefinition) scheduler.require(d, Step.Populated);
		auto init = cast(VariableDeclaration) d.dscope.resolve("init");
		
		return init.value;
	}
	/*
	Expression visit(ClassDefinition d) {
		return new NullLiteral(location, new SymbolType(d.location, d));
	}
	*/
}

