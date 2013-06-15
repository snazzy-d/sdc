module d.semantic.type;

import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

import std.algorithm;
import std.array;

final class TypeVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Type visit(Type t) /* out(result) {
		assert(t.canonical, "Canonical type must be set.");
	} body */ {
		auto oldQualifier = qualifier;
		scope(exit) qualifier = oldQualifier;
		
		qualifier = t.qualifier = t.qualifier.add(qualifier);
		
		return this.dispatch(t);
	}
	
	Type visit(BooleanType t) {
		return t;
	}
	
	Type visit(IntegerType t) {
		return t;
	}
	
	Type visit(FloatType t) {
		return t;
	}
	
	Type visit(CharacterType t) {
		return t;
	}
	
	Type visit(VoidType t) {
		return t;
	}
	
	Type visit(TypeofType t) {
		t.expression = pass.visit(t.expression);
		
		return t.expression.type;
	}
	
	auto handleSuffixType(T, A...)(T t, A args) if(is(T : SuffixType)) {
		t.type = visit(t.type);
		
		if(t.type.canonical is t.type) {
			t.canonical = t;
		} else {
			t.canonical = new T(t.canonical, args);
		}
		
		return t;
	}
	
	Type visit(PointerType t) {
		return handleSuffixType(t);
	}
	
	Type visit(SliceType t) {
		return handleSuffixType(t);
	}
	
	Type visit(StaticArrayType t) {
		t.size = pass.visit(t.size);
		
		return handleSuffixType(t, t.size);
	}
	
	Type visit(AliasType t) {
		scheduler.require(t.dalias);
		t.canonical = t.dalias.type.canonical;
		
		return t.dalias.type;
	}
	
	Type visit(StructType t) {
		t.canonical = t;
		
		return t;
	}
	
	Type visit(ClassType t) {
		t.canonical = t;
		
		return t;
	}
	
	Type visit(EnumType t) {
		t.canonical = t;
		
		return t;
	}
	
	Type visit(FunctionType t) {
		// Go to pass to reset qualifier accumulation.
		t.returnType = pass.visit(t.returnType);
		t.canonical = t;
		
		return t;
	}
	
	Type visit(DelegateType t) {
		return visit(cast(FunctionType) t);
	}
	
	Type visit(IdentifierType t) {
		return pass.visit(t.identifier).apply!((identified) {
			static if(is(typeof(identified) : Type)) {
				return visit(identified);
			} else {
				return pass.raiseCondition!Type(t.identifier.location, t.identifier.name ~ " isn't an type.");
			}
		})();
	}
}

