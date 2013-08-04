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
	
	ParamType visit(ParamAstType t) {
		auto qt = visit(QualAstType(t.type, t.qualifier));
		
		return ParamType(qt, t.isRef);
	}
	
	QualType visit(TypeQualifier q, QualAstType t) {
		return this.dispatch(t.qualifier.add(q), t.type);
	}
	
	QualType visit(TypeQualifier q, BuiltinType t) {
		return QualType(t, q);
	}
	/+
	QualType visit(TypeofType t) {
		auto e = pass.visit(t.expression);
		
		return e.type;
	}
	+/
	QualType visit(TypeQualifier q, AstPointerType t) {
		return QualType(new PointerType(visit(q, t.pointed)), q);
	}
	
	QualType visit(TypeQualifier q, AstSliceType t) {
		return QualType(new SliceType(visit(q, t.sliced)), q);
	}
	/+
	Type visit(TypeQualifier q, d.ast.type.ArrayType t) {
		t.size = pass.visit(q, t.size);
		
		return handleSuffixType(t, t.size);
	}
	+/
	QualType visit(TypeQualifier q, AstFunctionType t) {
		auto returnType = visit(t.returnType);
		auto paramTypes = t.paramTypes.map!(t => visit(t)).array();
		
		return QualType(new FunctionType(t.linkage, returnType, paramTypes, t.isVariadic), q);
	}
	
	QualType visit(TypeQualifier q, AstDelegateType t) {
		auto returnType = visit(t.returnType);
		auto context = visit(t.context);
		auto paramTypes = t.paramTypes.map!(t => visit(t)).array();
		
		return QualType(new DelegateType(t.linkage, returnType, context, paramTypes, t.isVariadic), q);
	}
	
	QualType visit(TypeQualifier q, IdentifierType t) {
		return pass.visit(t.identifier).apply!((identified) {
			static if(is(typeof(identified) : QualType)) {
				return QualType(identified.type, q.add(identified.qualifier));
			} else {
				return pass.raiseCondition!Type(t.identifier.location, t.identifier.name ~ " isn't an type.");
			}
		})();
	}
}

