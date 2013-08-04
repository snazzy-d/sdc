module d.semantic.caster;

import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ast.base;

import d.ir.expression;
import d.ir.type;

import d.exception;
import d.location;

import std.algorithm;

final class Caster(bool isExplicit) {
	private SemanticPass pass;
	alias pass this;
	
	private Location location;
	
	private FromBuiltin fromBuiltin;
	private FromPointer fromPointer;
	private FromSlice fromSlice;
	// private FromFunction fromFunction;
	// private FromDelegate fromDelegate;
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		fromBuiltin		= new FromBuiltin();
		fromPointer		= new FromPointer();
		fromSlice		= new FromSlice();
		// fromFunction	= new FromFunction();
		// fromDelegate	= new FromDelegate();
	}
	
	// XXX: out contract disabled because it create memory corruption with dmd.
	Expression build(Location castLocation, QualType to, Expression e) /* out(result) {
		assert(result.type == to);
	} body */ {
		// If the expression is polysemous, we try the several meaning and exclude the ones that make no sense.
		if(auto asPolysemous = cast(PolysemousExpression) e) {
			auto oldBuildErrorNode = buildErrorNode;
			scope(exit) buildErrorNode = oldBuildErrorNode;
			
			buildErrorNode = true;
			
			Expression casted;
			foreach(candidate; asPolysemous.expressions) {
				// XXX: Remove that ! Controle flow with exceptions is crap.
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
		
		assert(to.type && e.type.type);
		
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = castLocation;
		
		auto kind = castFrom(e.type, to);
		return (kind == CastKind.Exact) ? e : new CastExpression(location, kind, to, e);
	}
	
	// FIXME: this shouldn't forward but bu the base.
	CastKind castFrom(QualType from, QualType to) {
		return castFrom(from.type, to.type);
	}
	
	CastKind castFrom(Type from, Type to) {
		from = peelAlias(from);
		to = peelAlias(to);
		
		if(from == to) {
			return CastKind.Exact;
		}
		
		auto ret = this.dispatch!((t) {
			return CastKind.Invalid;
		})(to, from);
		
		assert(ret != CastKind.Invalid, "Can't cast " ~ from.toString() ~ " to " ~ to.toString());
		
		return ret;
	}
	
	class FromBuiltin {
		CastKind visit(TypeKind from, Type to) {
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(from, to);
		}
		
		CastKind visit(TypeKind from, BuiltinType t) {
			auto to = t.kind;
			
			if(from == to) {
				return CastKind.Exact;
			}
			
			if(to == TypeKind.None) {
				return CastKind.Invalid;
			}
			
			final switch(from) with(TypeKind) {
				case None:
				case Void:
					return CastKind.Invalid;
				
				case Bool:
					if(isIntegral(to)) {
						return CastKind.Pad;
					}
					
					return CastKind.Invalid;
				
				case Char:
					from = integralOfChar(from);
					goto case Ubyte;
				
				case Wchar:
					from = integralOfChar(from);
					goto case Ushort;
				
				case Dchar:
					from = integralOfChar(from);
					goto case Uint;
				
				case Ubyte:
				case Ushort:
				case Uint:
				case Ulong:
				case Ucent:
				case Byte:
				case Short:
				case Int:
				case Long:
				case Cent:
					static if(isExplicit) {
						if(to == Bool) {
							return CastKind.IntegralToBool;
						}
					}
					
					if(!isIntegral(to)) {
						return CastKind.Invalid;
					}
					
					from = unsigned(from);
					to = unsigned(to);
					switch(to) {
						case Ubyte:
						case Ushort:
						case Uint:
						case Ulong:
						case Ucent:
							if(from == to) {
								return CastKind.Bit;
							} else if(from < to) {
								return CastKind.Pad;
							} else static if(isExplicit) {
								return CastKind.Trunc;
							} else {
								return CastKind.Invalid;
							}
						
						default:
							assert(0);
					}
				
				case Float:
				case Double:
				case Real:
				case Null:
					assert(0, "Not implemented");
			}
		}
		
		CastKind visit(TypeKind from, PointerType t) {
			if(from == TypeKind.Null) {
				return CastKind.Bit;
			}
			
			return CastKind.Invalid;
		}
		
		CastKind visit(TypeKind from, FunctionType t) {
			if(from == TypeKind.Null) {
				return CastKind.Bit;
			}
			
			return CastKind.Invalid;
		}
		
		static if(isExplicit) {
			CastKind visit(TypeKind from, EnumType t) {
				if(isIntegral(from)) {
					return visit(from, t.denum.type);
				}
				
				return CastKind.Invalid;
			}
		}
	}
	
	CastKind visit(Type to, BuiltinType t) {
		return fromBuiltin.visit(t.kind, to);
	}
	
	class FromPointer {
		QualType from;
		
		CastKind visit(QualType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(to);
		}
		
		CastKind visit(PointerType t) {
			// Cast to void* is kind of special.
			if(auto v = cast(BuiltinType) t.pointed.type) {
				if(v.kind == TypeKind.Void) {
					static if(isExplicit) {
						return CastKind.Bit;
					} else if(canConvert(from.qualifier, t.pointed.qualifier)) {
						return CastKind.Bit;
					} else {
						return CastKind.Invalid;
					}
				}
			}
			
			auto subCast = castFrom(from, t.pointed);
			
			switch(subCast) with(CastKind) {
				case Qual :
					if(canConvert(from.qualifier, t.pointed.qualifier)) {
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
						if(canConvert(from.qualifier, t.pointed.qualifier)) {
							return subCast;
						}
						
						return Invalid;
					
					default :
						return Invalid;
				}
			}
		}
		
		static if(isExplicit) {
			CastKind visit(FunctionType t) {
				return CastKind.Bit;
			}
		}
	}
	
	CastKind visit(Type to, PointerType t) {
		return fromPointer.visit(t.pointed, to);
	}
	
	class FromSlice {
		QualType from;
		
		CastKind visit(QualType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(to);
		}
		
		CastKind visit(SliceType t) {
			// Cast to void* is kind of special.
			if(auto v = cast(BuiltinType) t.sliced.type) {
				if(v.kind == TypeKind.Void) {
					static if(isExplicit) {
						return CastKind.Bit;
					} else if(canConvert(from.qualifier, t.sliced.qualifier)) {
						return CastKind.Bit;
					} else {
						return CastKind.Invalid;
					}
				}
			}
			
			auto subCast = castFrom(from, t.sliced);
			
			switch(subCast) with(CastKind) {
				case Qual :
					if(canConvert(from.qualifier, t.sliced.qualifier)) {
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
						if(canConvert(from.qualifier, t.sliced.qualifier)) {
							return subCast;
						}
						
						return Invalid;
					
					default :
						return Invalid;
				}
			}
		}
	}
	
	CastKind visit(Type to, SliceType t) {
		return fromSlice.visit(t.sliced, to);
	}
	
	CastKind visit(Type to, StructType t) {
		if(auto s = cast(StructType) to) {
			if(t.dstruct == s.dstruct) {
				return CastKind.Exact;
			}
		}
		
		return CastKind.Invalid;
	}
	
	CastKind visit(Type to, ClassType t) {
		// Automagically promote to base type.
		auto c = t.dclass;
		scheduler.require(c);
		
		// Stop at object.
		if(c.base != c.base.base) {
			return min(castFrom(new ClassType(c.base), to), CastKind.Bit);
		}
		
		return CastKind.Invalid;
	}
	
	CastKind visit(Type to, EnumType t) {
		// Automagically promote to base type.
		return castFrom(t.denum.type, to);
	}
	/+
	class FromFunction {
		FunctionType from;
		
		CastKind visit(FunctionType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(to);
		}
		
		CastKind visit(FunctionType t) {
			enum onFail = isExplicit ? CastKind.Bit : CastKind.Invalid;
			
			if(from.parameters.length != t.parameters.length) return onFail;
			if(from.isVariadic != t.isVariadic) return onFail;
			
			if(from.linkage != t.linkage) return onFail;
			
			auto level = castFrom(from.returnType, t.returnType);
			if(level < CastKind.Bit) return onFail;
			
			foreach(fromp, top; lockstep(from.parameters, t.parameters)) {
				if(fromp.isReference != top.isReference) return onFail;
				
				auto levelp = castFrom(fromp.type, top.type);
				if(levelp < CastKind.Bit) return onFail;
				if(fromp.isReference && levelp < CastKind.Qual) return onFail;
				
				level = min(level, levelp);
			}
			
			if (level < CastKind.Exact) return CastKind.Bit;
			
			// FIXME: this must be done at upper level.
			// return (from.qualifier == t.qualifier) ? CastKind.Exact : CastKind.Qual;
			return CastKind.Exact;
		}
		
		CastKind visit(PointerType t) {
			static if(isExplicit) {
				return CastKind.Bit;
			} else if(auto toType = cast(VoidType) t.type) {
				return CastKind.Bit;
			} else {
				return CastKind.Invalid;
			}
		}
	}
	
	CastKind visit(Type to, FunctionType t) {
		return fromFunction.visit(t, to);
	}
	
	class FromDelegate {
		DelegateType from;
		
		CastKind visit(DelegateType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(to);
		}
		
		CastKind visit(DelegateType t) {
			enum onFail = isExplicit ? CastKind.Bit : CastKind.Invalid;
			
			if(from.parameters.length != t.parameters.length) return onFail;
			if(from.isVariadic != t.isVariadic) return onFail;
			
			if(from.linkage != t.linkage) return onFail;
			
			auto level = castFrom(from.returnType, t.returnType);
			if(level < CastKind.Bit) return onFail;
			
			foreach(fromp, top; lockstep(from.parameters, t.parameters)) {
				if(fromp.isReference != top.isReference) return onFail;
				
				auto levelp = castFrom(fromp.type, top.type);
				if(levelp < CastKind.Bit) return onFail;
				if(fromp.isReference && levelp < CastKind.Qual) return onFail;
				
				level = min(level, levelp);
			}
			
			if (level < CastKind.Exact) return CastKind.Bit;
			
			// FIXME: this must be done at upper level.
			// return (from.qualifier == t.qualifier) ? CastKind.Exact : CastKind.Qual;
			return CastKind.Exact;
		}
	}
	
	CastKind visit(Type to, DelegateType t) {
		return fromDelegate.visit(t, to);
	}
	+/
}

