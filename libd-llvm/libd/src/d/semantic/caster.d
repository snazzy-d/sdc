module d.semantic.caster;

import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ast.base;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.exception;
import d.location;

import std.algorithm;

auto buildImplicitCast(SemanticPass pass, Location location, QualType to, Expression e) {
	return build!false(pass, location, to, e);
}

auto buildExplicitCast(SemanticPass pass, Location location, QualType to, Expression e) {
	return build!true(pass, location, to, e);
}

CastKind implicitCastFrom(SemanticPass pass, QualType from, QualType to) {
	return Caster!false(pass).castFrom(from, to);
}

CastKind explicitCastFrom(SemanticPass pass, QualType from, QualType to) {
	return Caster!true(pass).castFrom(from, to);
}

private:

Expression build(bool isExplicit)(SemanticPass pass, Location location, QualType to, Expression e) {
	// If the expression is polysemous, we try the several meaning and exclude the ones that make no sense.
	if(auto asPolysemous = cast(PolysemousExpression) e) {
		auto oldBuildErrorNode = pass.buildErrorNode;
		scope(exit) pass.buildErrorNode = oldBuildErrorNode;
		
		pass.buildErrorNode = true;
		
		Expression casted;
		foreach(candidate; asPolysemous.expressions) {
			// XXX: Remove that ! Controle flow with exceptions is crap.
			try {
				candidate = build!isExplicit(pass, location, to, candidate);
			} catch(CompileException e) {
				continue;
			}
			
			if(cast(ErrorExpression) candidate) {
				continue;
			}
			
			if(casted) {
				return pass.raiseCondition!Expression(location, "Ambiguous.");
			}
			
			casted = candidate;
		}
		
		if(casted) {
			return casted;
		}
		
		return pass.raiseCondition!Expression(e.location, "No match found.");
	}
	
	assert(to.type && e.type.type);
	
	auto kind = Caster!isExplicit(pass).castFrom(e.type, to);
	switch(kind) with(CastKind) {
		case Exact :
			return e;
		
		default :
			return new CastExpression(location, kind, to, e);
		
		case Invalid :
			return pass.raiseCondition!Expression(location, "Can't cast " ~ e.type.toString() ~ " to " ~ to.toString());
	}
}

struct Caster(bool isExplicit) {
	// XXX: Used only to get to super class, should probably go away.
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	// FIXME: handle qualifiers.
	CastKind castFrom(QualType from, QualType to) {
		return castFrom(from.type, to.type);
	}
	
	CastKind castFrom(ParamType from, ParamType to) {
		if(from.isRef != to.isRef) return CastKind.Invalid;
		
		auto k = castFrom(from.type, to.type);
		if(from.isRef && k < CastKind.Qual) return CastKind.Invalid;
		
		return k;
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
		
		return ret;
	}
	
	struct FromBuiltin {
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
		return FromBuiltin().visit(t.kind, to);
	}
	
	struct FromPointer {
		Caster caster;
		
		this(Caster caster) {
			this.caster = caster;
		}
		
		CastKind visit(QualType from, Type to) {
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(from, to);
		}
		
		CastKind visit(QualType from, PointerType t) {
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
			
			auto subCast = caster.castFrom(from, t.pointed);
			
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
			CastKind visit(QualType from, FunctionType t) {
				return CastKind.Bit;
			}
		}
	}
	
	CastKind visit(Type to, PointerType t) {
		return FromPointer(this).visit(t.pointed, to);
	}
	
	struct FromSlice {
		Caster caster;
		
		this(Caster caster) {
			this.caster = caster;
		}
		
		CastKind visit(QualType from, Type to) {
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(from, to);
		}
		
		CastKind visit(QualType from, SliceType t) {
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
			
			auto subCast = caster.castFrom(from, t.sliced);
			
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
		return FromSlice(this).visit(t.sliced, to);
	}
	
	CastKind visit(Type to, StructType t) {
		if(auto s = cast(StructType) to) {
			if(t.dstruct is s.dstruct) {
				return CastKind.Exact;
			}
		}
		
		return CastKind.Invalid;
	}
	
	private auto castClass(Class from, Class to) {
		if(from is to) {
			return CastKind.Exact;
		}
		
		// Stop at object.
		while(from !is from.base) {
			// Automagically promote to base type.
			from = from.base;
			
			if(from is to) {
				return CastKind.Bit;
			}
		}
		
		return CastKind.Invalid;
	}
	
	CastKind visit(Type to, ClassType t) {
		if(auto ct = cast(ClassType) to) {
			scheduler.require(t.dclass, Step.Signed);
			return castClass(t.dclass, ct.dclass);
		}
		
		return CastKind.Invalid;
	}
	
	CastKind visit(Type to, EnumType t) {
		// Automagically promote to base type.
		return castFrom(t.denum.type, to);
	}
	
	struct FromFunction {
		Caster caster;
		
		this(Caster caster) {
			this.caster = caster;
		}
		
		CastKind visit(FunctionType from, Type to) {
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(from, to);
		}
		
		CastKind visit(FunctionType from, FunctionType t) {
			enum onFail = isExplicit ? CastKind.Bit : CastKind.Invalid;
			
			if(from.paramTypes.length != t.paramTypes.length) return onFail;
			if(from.isVariadic != t.isVariadic) return onFail;
			
			if(from.linkage != t.linkage) return onFail;
			
			auto k = caster.castFrom(from.returnType.type, t.returnType.type);
			if(k < CastKind.Bit) return onFail;
			
			import std.range;
			foreach(fromp, top; lockstep(from.paramTypes, t.paramTypes)) {
				// Parameters are contrevariant.
				auto kp = caster.castFrom(top, fromp);
				if(kp < CastKind.Bit) return onFail;
				
				k = min(k, kp);
			}
			
			return (k < CastKind.Exact) ? CastKind.Bit : CastKind.Exact;
		}
		
		CastKind visit(FunctionType from, PointerType t) {
			static if(isExplicit) {
				return CastKind.Bit;
			} else if(auto to = cast(BuiltinType) t.pointed.type) {
				// FIXME: qualifier.
				return (to.kind == TypeKind.Void) ? CastKind.Bit : CastKind.Invalid;
			} else {
				return CastKind.Invalid;
			}
		}
	}
	
	CastKind visit(Type to, FunctionType t) {
		return FromFunction(this).visit(t, to);
	}
	
	struct FromDelegate {
		Caster caster;
		
		this(Caster caster) {
			this.caster = caster;
		}
		
		CastKind visit(DelegateType from, Type to) {
			return this.dispatch!((t) {
				return CastKind.Invalid;
			})(from, to);
		}
		
		CastKind visit(DelegateType from, DelegateType t) {
			enum onFail = isExplicit ? CastKind.Bit : CastKind.Invalid;
			
			if(from.paramTypes.length != t.paramTypes.length) return onFail;
			if(from.isVariadic != t.isVariadic) return onFail;
			
			if(from.linkage != t.linkage) return onFail;
			
			auto k = caster.castFrom(from.returnType.type, t.returnType.type);
			if(k < CastKind.Bit) return onFail;
			
			import std.range;
			foreach(fromp, top; lockstep(from.paramTypes, t.paramTypes)) {
				// Parameters are contrevariant.
				auto kp = caster.castFrom(top, fromp);
				if(kp < CastKind.Bit) return onFail;
				
				k = min(k, kp);
			}
			
			return (k < CastKind.Exact) ? CastKind.Bit : CastKind.Exact;
		}
	}
	
	CastKind visit(Type to, DelegateType t) {
		return FromDelegate(this).visit(t, to);
	}
}

