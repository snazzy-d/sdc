module d.semantic.type;

import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.base;
import d.ast.declaration;
import d.ast.type;

import d.ir.type;

import std.algorithm;
import std.array;

alias PointerType = d.ir.type.PointerType;
alias SliceType = d.ir.type.SliceType;
alias FunctionType = d.ir.type.FunctionType;
alias DelegateType = d.ir.type.DelegateType;

final class TypeVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	QualType visit(QualAstType t) {
		return visit(TypeQualifier.Mutable, t);
	}
	
	QualType visit(TypeQualifier q, QualAstType t) {
		q = t.qualifier.add(q);
		
		return QualType(this.dispatch(q, t.type), q);
	}
	
	Type visit(TypeQualifier q, BuiltinType t) {
		return t;
	}
	/+
	QualType visit(TypeofType t) {
		auto e = pass.visit(t.expression);
		
		return e.type;
	}
	+/
	Type visit(TypeQualifier q, AstPointerType t) {
		return new PointerType(visit(q, t.pointed));
	}
	
	Type visit(TypeQualifier q, AstSliceType t) {
		return new SliceType(visit(q, t.sliced));
	}
	/+
	Type visit(TypeQualifier q, d.ast.type.ArrayType t) {
		t.size = pass.visit(q, t.size);
		
		return handleSuffixType(t, t.size);
	}
	+/
	Type visit(TypeQualifier q, AstFunctionType t) {
		// Go to pass to reset qualifier accumulation.
		auto returnType = ParamType(pass.visit(QualAstType(t.returnType.type)));
		returnType.qualifier = t.returnType.qualifier;
		returnType.isRef = t.returnType.isRef;
		
		auto paramTypes = t.paramTypes.map!(t => ParamType(pass.visit(QualAstType(t.type)))).array();
		foreach(i, ref p; paramTypes) {
			p.qualifier = t.paramTypes[i].qualifier;
			p.isRef = t.paramTypes[i].isRef;
		}
		
		return new FunctionType(t.linkage, returnType, paramTypes, t.isVariadic);
	}
	/+
	Type visit(TypeQualifier q, AstDelegateType t) {
		return visit(cast(FunctionType) t);
	}
	
	Type visit(TypeQualifier q, IdentifierType t) {
		return pass.visit(t.identifier).apply!((identified) {
			static if(is(typeof(identified) : QualType)) {
				return identified;
			} else {
				return pass.raiseCondition!Type(t.identifier.location, t.identifier.name ~ " isn't an type.");
			}
		})();
	}
	+/
}

