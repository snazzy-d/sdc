module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.symbol;
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
	
	Location location;
	
	this(SemanticPass pass, Location location) {
		this.pass = pass;
		this.location = location;
	}
	
	E visit(QualType t) {
		auto e = this.dispatch!((t) {
			return pass.raiseCondition!E(location, "Type " ~ typeid(t).toString() ~ " has no initializer.");
		})(peelAlias(t).type);
		
		e.type.qualifier = t.qualifier;
		return e;
	}
	
	E visit(BuiltinType t) {
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
	
	E visit(PointerType t) {
		return new NullLiteral(location, QualType(t));
	}
	
	E visit(SliceType t) {
		auto sizeT = cast(BuiltinType) peelAlias(pass.object.getSizeT().type).type;
		assert(sizeT !is null, "getSizeT().type.type does not cast to BuiltinType");
		CompileTimeExpression[] init = [
			new NullLiteral(location, t.sliced),
			new IntegerLiteral!false(location, 0UL, sizeT.kind)
		];
		
		// XXX: Should cast to size_t, but buildImplicitCast doesn't produce CompileTimeExpressions.
		return new CompileTimeTupleExpression(location, QualType(t), init);
	}

	E visit(ArrayType t) {
		E[] elements;
		elements.length = t.size;
		elements[] = visit(t.elementType);
		
		static if (isCompileTime) {
			return new CompileTimeTupleExpression(location, QualType(t), elements);
		} else {
			return new TupleExpression(location, QualType(t), elements);
		}
	}
	
	private Expression getTemporary(Expression value) {
		import d.context;
		auto v = new Variable(value.location, value.type, BuiltinName!"", value);
		v.step = Step.Processed;
		
		return new VariableExpression(value.location, v);
	}
	
	E visit(StructType t) {
		auto s = t.dstruct;
		scheduler.require(s, Step.Populated);
		
		import d.context;
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
				auto f = cast(Field) s.members.filter!(m => m.name == BuiltinName!"__ctx").front;
				assert(f, "Context must be a field");
				
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
				
				return new BinaryExpression(location, QualType(t), BinaryOp.Comma, assign, v);
			}
		}
		
		return v;
	}
	
	E visit(ClassType t) {
		static if(isNew) {
			auto c = t.dclass;
			scheduler.require(c);
			
			import std.algorithm, std.array;
			auto fields = c.members.map!(m => cast(Field) m).filter!(f => !!f).map!(f => f.value).array();
			
			fields[0] = new VtblExpression(location, c);
			if (c.hasContext) {
				import d.context;
				foreach(f; c.members.filter!(m => m.name == BuiltinName!"__ctx").map!(m => cast(Field) m)) {
					assert(f, "Context must be a field");
					
					auto pt = cast(PointerType) f.type.type;
					assert(pt);
					
					auto ct = cast(ContextType) pt.pointed.type;
					assert(ct);
					
					fields[f.index] = new UnaryExpression(location, QualType(pt), UnaryOp.AddressOf, new ContextExpression(location, ct));
				}
			}
			
			return new TupleExpression(location, QualType(new TupleType(fields.map!(f => f.type).array())), fields);
		} else {
			return new NullLiteral(location, QualType(t));
		}
	}
	
	E visit(FunctionType t) {
		return new NullLiteral(location, QualType(t));
	}
}

