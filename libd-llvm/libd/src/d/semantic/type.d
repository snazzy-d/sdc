module d.semantic.type;

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
alias ArrayType = d.ir.type.ArrayType;

struct TypeVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private TypeQualifier qualifier;
	
	this(SemanticPass pass, TypeQualifier qualifier = TypeQualifier.Mutable) {
		this.pass = pass;
		this.qualifier = qualifier;
	}
	
	TypeVisitor withStorageClass(StorageClass stc) {
		auto q = stc.hasQualifier
			? qualifier.add(stc.qualifier)
			: qualifier;
		
		return TypeVisitor(pass, q);
	}
	
	QualType visit(QualAstType t) {
		qualifier = qualifier.add(t.qualifier);
		return this.dispatch(t.type);
	}
	
	ParamType visit(ParamAstType t) {
		auto qt = visit(QualAstType(t.type, t.qualifier));
		return ParamType(qt, t.isRef, t.isFinal);
	}
	
	QualType visit(BuiltinType t) {
		return QualType(t, qualifier);
	}
	
	QualType visit(TypeofType t) {
		import d.semantic.expression;
		auto ret = ExpressionVisitor(pass).visit(t.expression).type;
		
		return TypeRequalifier(qualifier).visit(ret);
	}
	
	QualType visit(AstPointerType t) {
		return QualType(new PointerType(visit(t.pointed)), qualifier);
	}
	
	QualType visit(AstSliceType t) {
		return QualType(new SliceType(visit(t.sliced)), qualifier);
	}
	
	QualType visit(AstArrayType t) {
		auto elementType = visit(t.elementType);
		
		import d.semantic.caster, d.semantic.expression, d.ir.expression;
		auto size = evalIntegral(buildImplicitCast(
			pass,
			t.size.location,
			pass.object.getSizeT().type,
			ExpressionVisitor(pass).visit(t.size),
		));
		
		return QualType(new ArrayType(elementType, size));
	}
	
	QualType visit(AstFunctionType t) {
		auto oldQualifier = qualifier;
		scope(exit) qualifier = oldQualifier;
		
		qualifier = TypeQualifier.Mutable;
		
		auto returnType = visit(t.returnType);
		auto paramTypes = t.paramTypes.map!(t => visit(t)).array();
		
		return QualType(new FunctionType(t.linkage, returnType, paramTypes, t.isVariadic), oldQualifier);
	}
	
	QualType visit(AstDelegateType t) {
		auto context = visit(t.context);
		
		auto oldQualifier = qualifier;
		scope(exit) qualifier = oldQualifier;
		
		qualifier = TypeQualifier.Mutable;
		
		auto returnType = visit(t.returnType);
		auto paramTypes = t.paramTypes.map!(t => visit(t)).array();
		
		return QualType(new DelegateType(t.linkage, returnType, context, paramTypes, t.isVariadic), oldQualifier);
	}
	
	QualType visit(IdentifierType t) {
		import d.semantic.identifier;
		return SymbolResolver!(delegate QualType(identified) {
			static if(is(typeof(identified) : QualType)) {
				return TypeRequalifier(qualifier).visit(identified);
			} else {
				return pass.raiseCondition!Type(t.identifier.location, t.identifier.name.toString(pass.context) ~ " isn't an type.");
			}
		})(pass).visit(t.identifier);
	}
}

struct TypeRequalifier {
	private TypeQualifier qualifier;
	
	this(TypeQualifier qualifier) {
		this.qualifier = qualifier;
	}
	
	QualType visit(QualType t) {
		auto nq = t.qualifier.add(qualifier);
		if (t.qualifier == nq) {
			return t;
		}
		
		qualifier = nq;
		return QualType(this.dispatch(t.type), nq);
	}
	
	Type visit(BuiltinType t) {
		return t;
	}
	
	Type visit(PointerType t) {
		return new PointerType(visit(t.pointed));
	}
	
	Type visit(SliceType t) {
		return new SliceType(visit(t.sliced));
	}
	
	Type visit(ArrayType t) {
		return new SliceType(visit(t.elementType));
	}
}

