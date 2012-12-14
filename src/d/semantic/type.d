module d.semantic.type;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

final class TypeVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Type visit(Type t) {
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
	
	auto handleSuffixType(T)(T t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(PointerType t) {
		return handleSuffixType(t);
	}
	
	Type visit(SliceType t) {
		return handleSuffixType(t);
	}
	
	Type visit(StaticArrayType t) {
		return handleSuffixType(t);
	}
	
	Type visit(EnumType t) {
		return handleSuffixType(t);
	}
	
	Type visit(FunctionType t) {
		t.returnType = visit(t.returnType);
		
		return t;
	}
	
	Type visit(IdentifierType t) {
		auto resolved = pass.visit(t.identifier);
		
		if(auto asType = resolved.asType()) {
			return pass.visit(asType);
		}
		
		// TODO: ambiguous deambiguation.
		return compilationCondition!Type(t.location, t.identifier.name ~ " isn't an expression.");
	}
	
	Type visit(SymbolType t) {
		t.symbol = cast(TypeSymbol) scheduler.require(t.symbol);
		
		return t;
	}
}

