module d.semantic.type;

import d.semantic.semantic;

import d.ast.base;
import d.ast.type;

import d.ir.type;

// XXX: module level for UFCS.
import std.algorithm, std.array;

struct TypeVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private TypeQualifier qualifier;
	
	this(SemanticPass pass, TypeQualifier qualifier = TypeQualifier.Mutable) {
		this.pass = pass;
		this.qualifier = qualifier;
	}
	
	import d.ast.declaration;
	TypeVisitor withStorageClass(StorageClass stc) {
		return TypeVisitor(
			pass,
			stc.hasQualifier
				? qualifier.add(stc.qualifier)
				: qualifier,
		);
	}
	
	Type visit(AstType t) {
		return this.dispatch(t);
	}
	
	Type visit(QualAstType t) {
		return visit(t.type).qualify(t.qualifier);
	}
	
	ParamType visit(ParamAstType t) {
		return visit(t.type)
			.qualify(t.qualifier)
			.getParamType(t.isRef, t.isFinal);
	}
	
	Type visit(BuiltinAstType t) {
		return Type.get(t.kind, qualifier);
	}
	
	Type visit(AstPointerType t) {
		return visit(t.pointed).getPointer(qualifier);
	}
	
	Type visit(AstSliceType t) {
		return visit(t.sliced).getSlice(qualifier);
	}
	
	Type visit(AstArrayType t) {
		import d.semantic.caster, d.semantic.expression, d.ir.expression;
		auto size = evalIntegral(buildImplicitCast(
			pass,
			t.size.location,
			pass.object.getSizeT().type,
			ExpressionVisitor(pass).visit(t.size),
		));
		
		return visit(t.elementType).getArray(size, qualifier);
	}
	
	Type visit(AstFunctionType t) {
		auto oldQualifier = qualifier;
		scope(exit) qualifier = oldQualifier;
		
		qualifier = TypeQualifier.Mutable;
		
		auto returnType = visit(t.returnType);
		auto paramTypes = t.paramTypes.map!(t => visit(t)).array();
		
		alias FunctionType = d.ir.type.FunctionType;
		return FunctionType(t.linkage, returnType, paramTypes, t.isVariadic).getType(oldQualifier);
	}
	
	Type visit(AstDelegateType t) {
		auto contextType = visit(t.context);
		
		auto oldQualifier = qualifier;
		scope(exit) qualifier = oldQualifier;
		
		qualifier = TypeQualifier.Mutable;
		
		auto returnType = visit(t.returnType);
		auto paramTypes = t.paramTypes.map!(t => visit(t)).array();
		
		alias FunctionType = d.ir.type.FunctionType;
		return FunctionType(t.linkage, returnType, contextType, paramTypes, t.isVariadic).getType(oldQualifier);
	}
	
	Type visit(IdentifierType t) {
		import d.semantic.identifier;
		return SymbolResolver!(delegate Type(identified) {
			static if(is(typeof(identified) : Type)) {
				return identified.qualify(qualifier);
			} else {
				return pass.raiseCondition!Type(t.identifier.location, t.identifier.name.toString(pass.context) ~ " isn't an type.");
			}
		})(pass).visit(t.identifier);
	}
	
	Type visit(TypeofType t) {
		import d.semantic.expression;
		return ExpressionVisitor(pass).visit(t.expression).type.qualify(qualifier);
	}
}

