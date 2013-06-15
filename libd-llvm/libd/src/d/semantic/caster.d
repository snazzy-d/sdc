module d.semantic.caster;

import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.exception;
import d.location;

import std.algorithm;
import std.range;

// FIXME: isn't reentrant at all.
final class Caster(bool isExplicit) {
	private SemanticPass pass;
	alias pass this;
	
	private Location location;
	
	private FromBoolean fromBoolean;
	private FromInteger fromInteger;
	private FromCharacter fromCharacter;
	private FromPointer fromPointer;
	private FromFunction fromFunction;
	private FromDelegate fromDelegate;
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		fromBoolean		= new FromBoolean();
		fromInteger		= new FromInteger();
		// fromFloat		= new FromFloat();
		fromCharacter	= new FromCharacter();
		fromPointer		= new FromPointer();
		fromFunction	= new FromFunction();
		fromDelegate	= new FromDelegate();
	}
	
	// XXX: out contract disabled because it create memory corruption with dmd.
	Expression build(Location castLocation, Type to, Expression e) /* out(result) {
		assert(result.type == to);
	} body */ {
		// If the expression is polysemous, we try the several meaning and exclude the ones that make no sense.
		if(auto asPolysemous = cast(PolysemousExpression) e) {
			auto oldBuildErrorNode = buildErrorNode;
			scope(exit) buildErrorNode = oldBuildErrorNode;
			
			buildErrorNode = true;
			
			Expression casted;
			foreach(candidate; asPolysemous.expressions) {
				try {
					candidate = build(castLocation, to, candidate);
				} catch(CompileException e) {
					continue;
				}
				
				if(cast(ErrorExpression) candidate) {
					continue;
				}
				
				if(casted) {
					return pass.raiseCondition!Expression(e.location, "Ambiguous.");
				}
				
				casted = candidate;
			}
			
			if(casted) {
				return casted;
			}
			
			return pass.raiseCondition!Expression(e.location, "No match found.");
		}
		
		assert(to && e.type);
		
		// Default initializer removal.
		if(typeid(e) is typeid(DefaultInitializer)) {
			return defaultInitializerVisitor.visit(e.location, to);
		}
		
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = castLocation;
		
		final switch(castFrom(e.type, to)) with(CastFlavor) {
			case Not :
				return pass.raiseCondition!Expression(e.location, (isExplicit?"Explicit":"Implicit") ~ " cast from " ~ e.type.toString() ~ " to " ~ to.toString() ~ " is not allowed");
			
			case Bool :
				Expression zero = makeLiteral(castLocation, 0);
				auto type = getPromotedType(castLocation, e.type, zero.type);
				
				zero = pass.buildImplicitCast(castLocation, type, zero);
				e = pass.buildImplicitCast(e.location, type, e);
				
				auto res = new NotEqualityExpression(castLocation, e, zero);
				res.type = to;
				
				return res;
			
			case Trunc :
				return new TruncateExpression(location, to, e);
			
			case Pad :
				return new PadExpression(location, to, e);
			
			case Bit :
			case Qual :
				return new BitCastExpression(location, to, e);
			
			case Exact :
				return e;
		}
	}
	
	CastFlavor castFrom(Type from, Type to) {
		if(from == to) {
			return CastFlavor.Exact;
		}
		
		return this.dispatch!((t) {
			return CastFlavor.Not;
		})(to, from);
	}
	
	class FromBoolean {
		CastFlavor visit(Type to) {
			return this.dispatch!((t) {
				return CastFlavor.Not;
			})(to);
		}
		
		CastFlavor visit(IntegerType to) {
			return CastFlavor.Pad;
		}
	}
	
	CastFlavor visit(Type to, BooleanType t) {
		return fromBoolean.visit(to);
	}
	
	class FromInteger {
		Integer from;
		
		CastFlavor visit(Integer from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastFlavor.Not;
			})(to);
		}
		
		static if(isExplicit) {
			CastFlavor visit(BooleanType t) {
				return CastFlavor.Bool;
			}
			
			CastFlavor visit(EnumType t) {
				// If the cast is explicit, then try to cast from enum base type.
				return visit(from, t.denum.type);
			}
		}
		
		CastFlavor visit(IntegerType t) {
			if(t.type == from) {
				return CastFlavor.Qual;
			} else if(t.type >> 1 == from >> 1) {
				// Same type except for signess.
				return CastFlavor.Bit;
			} else if(t.type > from) {
				return CastFlavor.Pad;
			} else static if(isExplicit) {
				return CastFlavor.Trunc;
			} else {
				return CastFlavor.Not;
			}
		}
	}
	
	CastFlavor visit(Type to, IntegerType t) {
		return fromInteger.visit(t.type, to);
	}
	
	/*
	CastFlavor visit(FloatType t) {
		return fromFloatType(t.type)).visit(type);
	}
	*/
	
	class FromCharacter {
		Character from;
		
		CastFlavor visit(Character from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastFlavor.Not;
			})(to);
		}
		
		CastFlavor visit(IntegerType t) {
			Integer i;
			final switch(from) with(Character) {
				case Char :
					i = Integer.Ubyte;
					break;
				
				case Wchar :
					i = Integer.Ushort;
					break;
				
				case Dchar :
					i = Integer.Uint;
					break;
			}
			
			// A best a bitcast.
			return min(fromInteger.visit(i, t), CastFlavor.Bit);
		}
		
		CastFlavor visit(CharacterType t) {
			if(t.type == from) {
				return CastFlavor.Qual;
			}
			
			// TODO: cast to upper char.
			return CastFlavor.Not;
		}
	}
	
	CastFlavor visit(Type to, CharacterType t) {
		return fromCharacter.visit(t.type, to);
	}
	
	class FromPointer {
		Type from;
		
		CastFlavor visit(Type from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastFlavor.Not;
			})(to);
		}
		
		CastFlavor visit(PointerType t) {
			// Cast to void* is kind of special.
			if(auto v = cast(VoidType) t.type) {
				static if(isExplicit) {
					return CastFlavor.Bit;
				} else if(canConvert(from.qualifier, t.type.qualifier)) {
					return CastFlavor.Bit;
				} else {
					return CastFlavor.Not;
				}
			}
			
			auto subCast = castFrom(from, t.type);
			
			switch(subCast) with(CastFlavor) {
				case Qual :
					if(canConvert(from.qualifier, t.type.qualifier)) {
						return Qual;
					}
					
					goto default;
				
				case Exact :
					return Qual;
				
				static if(isExplicit) {
					default :
						return Bit;
				} else {
					case Bit :
						if(canConvert(from.qualifier, t.type.qualifier)) {
							return subCast;
						}
						
						return Not;
					
					default :
						return Not;
				}
			}
		}
		
		static if(isExplicit) {
			CastFlavor visit(FunctionType t) {
				return CastFlavor.Bit;
			}
		}
	}
	
	CastFlavor visit(Type to, PointerType t) {
		return fromPointer.visit(t.type, to);
	}
	
	CastFlavor visit(Type to, ClassType t) {
		// Automagically promote to base type.
		auto c = t.dclass;
		scheduler.require(c);
		
		auto bases = c.bases;
		if(bases.length == 1) {
			return min(castFrom(bases[0], to), CastFlavor.Bit);
		}
		
		return CastFlavor.Not;
	}
	
	CastFlavor visit(Type to, EnumType t) {
		// Automagically promote to base type.
		return castFrom(t.denum.type, to);
	}
	
	class FromFunction {
		FunctionType from;
		
		CastFlavor visit(FunctionType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastFlavor.Not;
			})(to);
		}
		
		CastFlavor visit(FunctionType t) {
			enum onFail = isExplicit ? CastFlavor.Bit : CastFlavor.Not;
			
			if(from.parameters.length != t.parameters.length) return onFail;
			if(from.isVariadic != t.isVariadic) return onFail;
			
			if(from.linkage != t.linkage) return onFail;
			
			auto level = castFrom(from.returnType, t.returnType);
			if(level < CastFlavor.Bit) return onFail;
			
			foreach(fromp, top; lockstep(from.parameters, t.parameters)) {
				if(fromp.isReference != top.isReference) return onFail;
				
				auto levelp = castFrom(fromp.type, top.type);
				if(levelp < CastFlavor.Bit) return onFail;
				if(fromp.isReference && levelp < CastFlavor.Qual) return onFail;
				
				level = min(level, levelp);
			}
			
			if (level < CastFlavor.Exact) return CastFlavor.Bit;
			
			return (from.qualifier == t.qualifier) ? CastFlavor.Exact : CastFlavor.Qual;
		}
		
		CastFlavor visit(PointerType t) {
			static if(isExplicit) {
				return CastFlavor.Bit;
			} else if(auto toType = cast(VoidType) t.type) {
				return CastFlavor.Bit;
			} else {
				return CastFlavor.Not;
			}
		}
	}
	
	CastFlavor visit(Type to, FunctionType t) {
		return fromFunction.visit(t, to);
	}
	
	class FromDelegate {
		DelegateType from;
		
		CastFlavor visit(DelegateType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastFlavor.Not;
			})(to);
		}
		
		CastFlavor visit(DelegateType t) {
			enum onFail = isExplicit ? CastFlavor.Bit : CastFlavor.Not;
			
			if(from.parameters.length != t.parameters.length) return onFail;
			if(from.isVariadic != t.isVariadic) return onFail;
			
			if(from.linkage != t.linkage) return onFail;
			
			auto level = castFrom(from.returnType, t.returnType);
			if(level < CastFlavor.Bit) return onFail;
			
			foreach(fromp, top; lockstep(from.parameters, t.parameters)) {
				if(fromp.isReference != top.isReference) return onFail;
				
				auto levelp = castFrom(fromp.type, top.type);
				if(levelp < CastFlavor.Bit) return onFail;
				if(fromp.isReference && levelp < CastFlavor.Qual) return onFail;
				
				level = min(level, levelp);
			}
			
			if (level < CastFlavor.Exact) return CastFlavor.Bit;
			
			return (from.qualifier == t.qualifier) ? CastFlavor.Exact : CastFlavor.Qual;
		}
	}
	
	CastFlavor visit(Type to, DelegateType t) {
		return fromDelegate.visit(t, to);
	}
}

