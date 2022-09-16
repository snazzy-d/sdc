module d.semantic.type;

import d.semantic.semantic;

import d.ast.identifier;
import d.ast.type;

import d.ir.type;

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
			pass, stc.hasQualifier ? qualifier.add(stc.qualifier) : qualifier);
	}

	Type visit(AstType t) {
		return t.accept(this).qualify(t.qualifier);
	}

	ParamType visit(ParamAstType t) {
		return visit(t.getType()).getParamType(t.paramKind);
	}

	Type visit(BuiltinType t) {
		return Type.get(t, qualifier);
	}

	Type visit(Identifier i) {
		import d.semantic.identifier;
		return
			IdentifierResolver(pass).build(i).apply!(delegate Type(identified) {
				static if (is(typeof(identified) : Type)) {
					return identified.qualify(qualifier);
				} else {
					import d.ir.error;
					return getError(
						identified,
						i.location,
						i.toString(pass.context) ~ " ("
							~ typeid(identified).toString() ~ ") isn't an type"
					).type;
				}
			})();
	}

	Type visitPointerOf(AstType t) {
		return visit(t).getPointer(qualifier);
	}

	Type visitSliceOf(AstType t) {
		return visit(t).getSlice(qualifier);
	}

	Type visitArrayOf(AstExpression size, AstType t) {
		auto type = visit(t);

		import d.semantic.expression;
		return buildArray(ExpressionVisitor(pass).visit(size), type);
	}

	import d.ir.expression;
	private Type buildArray(Expression size, Type t) {
		import d.semantic.caster, d.semantic.expression;
		auto s = evalIntegral(
			buildImplicitCast(pass, size.location, pass.object.getSizeT().type,
			                  size));

		assert(s <= uint.max, "Array larger than uint.max are not supported");
		return t.getArray(cast(uint) s, qualifier);
	}

	Type visitMapOf(AstType key, AstType t) {
		visit(t);
		visit(key);
		assert(0, "Map are not implemented.");
	}

	Type visitBracketOf(Identifier ikey, AstType t) {
		auto type = visit(t);

		import d.semantic.identifier, d.ir.symbol;
		return IdentifierResolver(pass)
			.build(ikey).apply!(delegate Type(identified) {
				alias T = typeof(identified);
				static if (is(T : Type)) {
					assert(0, "Not implemented.");
				} else static if (is(T : Expression)) {
					return buildArray(identified, type);
				} else if (auto v = cast(ValueTemplateParameter) identified) {
					return Pattern(type, v).getType();
				} else {
					import d.ir.error;
					return getError(
						identified,
						ikey.location,
						ikey.toString(pass.context)
							~ " isn't an type or an expression"
					).type;
				}
			})();
	}

	Type visit(FunctionAstType t) {
		auto ctxCount = t.contexts.length;
		auto f = t.getFunction();

		ParamType[] paramTypes;
		paramTypes.length = f.parameters.length;

		auto oldQualifier = qualifier;
		scope(exit) qualifier = oldQualifier;

		foreach (i; 0 .. ctxCount) {
			paramTypes[i] = visit(f.parameters[i]);
		}

		qualifier = TypeQualifier.Mutable;

		auto returnType = visit(t.returnType);
		foreach (i; ctxCount .. paramTypes.length) {
			paramTypes[i] = visit(f.parameters[i]);
		}

		return FunctionType(t.linkage, returnType, paramTypes, t.isVariadic)
			.getDelegate(ctxCount).getType(oldQualifier);
	}

	import d.ast.expression;
	Type visit(AstExpression e) {
		import d.semantic.expression;
		return ExpressionVisitor(pass).visit(e).type.qualify(qualifier);
	}

	Type visitTypeOfReturn() {
		assert(0, "typeof(return) is not implemented.");
	}
}
