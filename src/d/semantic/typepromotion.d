module d.semantic.typepromotion;

import d.semantic.base;

import d.ast.type;
import d.ast.adt; // For enum types.

import sdc.location;

import std.algorithm;

Type getPromotedType(Location location, Type t1, Type t2) {
	// If an unresolved type come here, the pass wil run again so we just skip.
	if(!(t1 && t2)) return null;
	
	final class T2Handler {
		Integer t1type;
		
		this(Integer t1type) {
			this.t1type = t1type;
		}
		
		Type visit(Type t) {
			return this.dispatch!(function Type(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Type visit(BooleanType t) {
			return new IntegerType(location, max(t1type, Integer.Int));
		}
		
		Type visit(IntegerType t) {
			// Type smaller than int are promoted to int.
			auto t2type = max(t.type, Integer.Int);
			
			return new IntegerType(location, max(t1type, t2type));
		}
		
		Type visit(EnumType t) {
			if(auto asInt = cast(IntegerType) t.type) {
				return visit(asInt);
			}
			
			assert(0, "Enum are of type int.");
		}
	}
	
	final class T1Handler {
		Type visit(Type t) {
			return this.dispatch!(function Type(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Type visit(BooleanType t) {
			return (new T2Handler(Integer.Int)).visit(t2);
		}
		
		Type visit(IntegerType t) {
			return (new T2Handler(t.type)).visit(t2);
		}
		
		Type visit(CharacterType t) {
			// Should check for RHS. But will fail on implicit cast if LHS isn't the right type for now.
			return t;
		}
		
		Type visit(PointerType t) {
			// FIXME: check RHS.
			return t;
		}
		
		Type visit(EnumType t) {
			if(auto asInt = cast(IntegerType) t.type) {
				return visit(asInt);
			}
			
			assert(0, "Enum are of type int.");
		}
	}
	
	return (new T1Handler()).visit(t1);
}

