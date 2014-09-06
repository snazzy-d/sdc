module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.type;

import d.location;

alias InitBuilder = DefaultInitializerVisitor!(true, false);
alias InstanceBuilder = DefaultInitializerVisitor!(false, false);
alias NewBuilder = DefaultInitializerVisitor!(false, true);

private:
struct DefaultInitializerVisitor(bool isCompileTime, bool isNew) {
	static assert(!isCompileTime || !isNew);
	
	static if(isCompileTime) {
		alias E = CompileTimeExpression;
	} else {
		alias E = Expression;
	}
	
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	E visit(Location location, QualType t) {
		auto e = this.dispatch!((t) {
			return pass.raiseCondition!E(location, "Type " ~ typeid(t).toString() ~ " has no initializer.");
		})(location, peelAlias(t).type);
		
		e.type.qualifier = t.qualifier;
		return e;
	}
	
	E visit(Location location, BuiltinType t) {
		final switch(t.kind) with(TypeKind) {
			case None :
				assert(0,"none shall not be!");
			case Void :
				assert(0, "Void initializer not Implemented");
			
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
	
	E visit(Location location, PointerType t) {
		return new NullLiteral(location, QualType(t));
	}
	/+
	Expression visit(SliceType t) {
		// Convoluted way to create the array due to compiler limitations.
		Expression[] init = [new NullLiteral(location, t.type)];
		init ~= makeLiteral(location, 0UL);
		
		auto ret = new TupleExpression(location, init);
		ret.type = t;
		
		return ret;
	}
	+/
	E visit(Location location, ArrayType t) {
		return new VoidInitializer(location, QualType(t));
	}
	
	E visit(Location location, StructType t) {
		auto s = t.dstruct;
		scheduler.require(s, Step.Populated);
		
		import d.ir.symbol, d.context;
		auto init = cast(Variable) s.dscope.resolve(BuiltinName!"init");
		assert(init, "init must be defined");
		
		static if(isCompileTime) {
			auto v = cast(E) init.value;
			assert(v, "init must be a compile time expression");
		} else {
			auto v = init.value;
			if (s.hasContext) {
				v = getTemporary(v);
				
				import std.algorithm;
				auto f = s.members.map!(m => cast(Field) m).filter!(f => f !is null && f.index == 0).front;
				
				auto pt = cast(PointerType) f.type.type;
				assert(pt);
				
				auto ct = cast(ContextType) pt.pointed.type;
				assert(ct);
				
				auto assign = new BinaryExpression(
					location,
					f.type,
					BinaryOp.Assign,
					new FieldExpression(location, v, f),
					new UnaryExpression(location, QualType(pt), UnaryOp.AddressOf, new ContextExpression(location, ct)),
				);
				
				v = new BinaryExpression(location, QualType(t), BinaryOp.Comma, assign, v);
			}
		}
		
		return v;
	}
	
	private Expression getTemporary(Expression value) {
		import d.ir.symbol, d.context;
		auto v = new Variable(value.location, value.type, BuiltinName!"", value);
		v.step = Step.Processed;
		
		return new VariableExpression(value.location, v);
	}
	
	E visit(Location location, ClassType t) {
		static if(isNew) {
			auto c = t.dclass;
			scheduler.require(c);
			
			import d.ir.symbol;
			import std.algorithm, std.array;
			auto fields = c.members.map!(m => cast(Field) m).filter!(f => !!f).map!(f => f.value).array();
			
			fields[0] = new VtblExpression(location, c);
			return new TupleExpression(location, fields);
		} else {
			return new NullLiteral(location, QualType(t));
		}
	}
	
	E visit(Location location, FunctionType t) {
		return new NullLiteral(location, QualType(t));
	}
}

