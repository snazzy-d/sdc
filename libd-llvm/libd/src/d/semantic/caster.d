module d.semantic.caster;

import d.semantic.base;
import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.location;

// FIXME: isn't reentrant at all.
final class Caster(bool isExplicit) {
	private SemanticPass pass;
	alias pass this;
	
	private Location location;
	private Expression expression;
	
	private FromBoolean fromBoolean;
	private FromInteger fromInteger;
	private FromCharacter fromCharacter;
	private FromPointer fromPointer;
	private FromFunction fromFunction;
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		fromBoolean		= new FromBoolean();
		fromInteger		= new FromInteger();
		// fromFloat		= new FromFloat();
		fromCharacter	= new FromCharacter();
		fromPointer		= new FromPointer();
		fromFunction	= new FromFunction();
	}
	
	// XXX: out contract disabled because it create memory corruption with dmd.
	Expression build(Location castLocation, Type to, Expression e) /* out(result) {
		assert(result.type == to);
	} body */ {
		/*
		import sdc.terminal;
		outputCaretDiagnostics(e.location, "Cast " ~ typeid(e).toString() ~ " to " ~ typeid(to).toString());
		//*/
		
		// If the expression is polysemous, we try the several meaning and exclude the ones that make no sense.
		if(auto asPolysemous = cast(PolysemousExpression) e) {
			Expression[] casted;
			foreach(candidate; asPolysemous.expressions) {
				import sdc.compilererror;
				try {
					casted ~= build(castLocation, to, candidate);
				} catch(CompilerError ce) {}
			}
			
			if(casted.length == 1) {
				return casted[0];
			} else if(casted.length > 1 ) {
				return compilationCondition!Expression(e.location, "Ambiguous.");
			} else {
				return compilationCondition!Expression(e.location, "No match found.");
			}
		}
		
		assert(to && e.type);
		
		// Default initializer removal.
		if(typeid(e) is typeid(DefaultInitializer)) {
			return defaultInitializerVisitor.visit(e.location, to);
		}
		
		// Nothing to cast.
		if(e.type == to) return e;
		
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = castLocation;
		
		auto oldExpression = expression;
		scope(exit) expression = oldExpression;
		
		expression = e;
		
		return castFrom(e.type, to);
	}
	
	private Expression castFrom(Type from, Type to) {
		return this.dispatch!(delegate Expression(Type t) {
			auto msg = typeid(t).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(t.location, msg);
			outputCaretDiagnostics(location, msg);
			
			outputCaretDiagnostics(to.location, "to " ~ typeid(to).toString());
			
			assert(0, msg);
		})(to, from);
	}
	
	class FromBoolean {
		Expression visit(Type to) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(to);
		}
		
		Expression visit(IntegerType to) {
			return new PadExpression(location, to, expression);
		}
	}
	
	Expression visit(Type to, BooleanType t) {
		return fromBoolean.visit(to);
	}
	
	class FromInteger {
		Integer from;
		
		Expression visit(Integer from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(to);
		}
		
		static if(isExplicit) {
			Expression visit(BooleanType t) {
				Expression zero = makeLiteral(location, 0);
				auto type = getPromotedType(location, expression.type, zero.type);
				
				zero = pass.implicitCast(location, type, zero);
				expression = pass.implicitCast(expression.location, type, expression);
				
				auto res = new NotEqualityExpression(location, expression, zero);
				res.type = t;
				
				return res;
			}
			
			Expression visit(EnumType t) {
				// If the cast is explicit, then try to cast from enum base type.
				return new BitCastExpression(location, t, build(location, t.type, expression));
			}
		}
		
		Expression visit(IntegerType t) {
			if(t.type >> 1 == from >> 1) {
				// Same type except for signess.
				return new BitCastExpression(location, t, expression);
			} else if(t.type > from) {
				return new PadExpression(location, t, expression);
			} else static if(isExplicit) {
				return new TruncateExpression(location, t, expression);
			} else {
				import std.conv;
				return compilationCondition!Expression(expression.location, "Implicit cast from " ~ to!string(from) ~ " to " ~ to!string(t.type) ~ " is not allowed");
			}
		}
	}
	
	Expression visit(Type to, IntegerType t) {
		return fromInteger.visit(t.type, to);
	}
	
	/*
	Expression visit(FloatType t) {
		return fromFloatType(t.type)).visit(type);
	}
	*/
	
	class FromCharacter {
		Character from;
		
		Expression visit(Character from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(to);
		}
		
		Expression visit(IntegerType t) {
			Integer i;
			final switch(from) {
				case Character.Char :
					i = Integer.Ubyte;
					break;
				
				case Character.Wchar :
					i = Integer.Ushort;
					break;
				
				case Character.Dchar :
					i = Integer.Uint;
					break;
			}
			
			return fromInteger.visit(i, t);
		}
		
		Expression visit(CharacterType t) {
			if(t.type == from) {
				// We don't care about qualifier as characters are values types.
				return new BitCastExpression(location, t, expression);
			}
			
			return compilationCondition!Expression(location, "Invalid character cast.");
		}
	}
	
	Expression visit(Type to, CharacterType t) {
		return fromCharacter.visit(t.type, to);
	}
	
	class FromPointer {
		Type from;
		
		Expression visit(Type from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(to);
		}
		
		Expression visit(PointerType t) {
			static if(isExplicit) {
				return new BitCastExpression(location, t, expression);
			} else if(auto toType = cast(VoidType) t.type) {
				return new BitCastExpression(location, t, expression);
			} else {
				// Ugly hack :D
				auto subCast = castFrom(from, t.type);
				
				// If subCast is a bitcast, then it is safe to cast pointers.
				if(auto bt = cast(BitCastExpression) subCast) {
					static if(isExplicit) {
						enum isValid = true;
					} else {
						bool isValid = canConvert(from.qualifier, t.type.qualifier);
					}
					
					if(isValid) {
						bt.type = t;
						
						return bt;
					}
				}
				
				return compilationCondition!Expression(location, "Invalid pointer cast.");
			}
		}
		
		static if(isExplicit) {
			Expression visit(FunctionType t) {
				return new BitCastExpression(location, t, expression);
			}
		}
	}
	
	Expression visit(Type to, PointerType t) {
		return fromPointer.visit(t.type, to);
	}
	
	class FromFunction {
		FunctionType from;
		
		Expression visit(FunctionType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!(function Expression(Type t) {
				return compilationCondition!Expression(t.location, typeid(t).toString() ~ " is not supported.");
			})(to);
		}
		
		Expression visit(PointerType t) {
			static if(isExplicit) {
				return new BitCastExpression(location, t, expression);
			} else if(auto toType = cast(VoidType) t.type) {
				return new BitCastExpression(location, t, expression);
			} else {
				return compilationCondition!Expression(location, "invalid pointer cast.");
			}
		}
	}
	
	Expression visit(Type to, FunctionType t) {
		return fromFunction.visit(t, to);
	}
	
	Expression visit(Type to, EnumType t) {
		// Automagically promote to base type.
		return build(location, to, new BitCastExpression(location, t.type, expression));
	}
}

