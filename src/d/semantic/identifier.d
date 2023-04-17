module d.semantic.identifier;

import d.semantic.semantic;

import d.ast.identifier;

import d.ir.error;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import source.location;
import source.name;

alias Identifiable = Type.UnionType!(Symbol, Expression);

auto apply(alias handler)(Identifiable i) {
	alias Tag = typeof(i.tag);
	final switch (i.tag) with (Tag) {
		case Symbol:
			return handler(i.get!Symbol);

		case Expression:
			return handler(i.get!Expression);

		case Type:
			return handler(i.get!Type);
	}
}

/**
 * General entry point to resolve identifiers.
 *
 * The resolve method family will fallback on the symbol itself in case of ambiguity.
 * The build method family will post process the symbols to get to a type/expression.
 */
struct IdentifierResolver {
private:
	SemanticPass pass;
	alias pass this;

	Expression thisExpr;

public:
	this(SemanticPass pass) {
		this.pass = pass;
	}

	~this() {
		if (thisExpr is null) {
			return;
		}

		auto e = getError(thisExpr, thisExpr.location,
		                  "thisExpr has not been consumed");

		import source.exception;
		throw new CompileException(e.location, e.message);
	}

	Identifiable build(Identifier i) {
		return postProcess(i.location, IdentifierVisitor(&this).visit(i));
	}

	Identifiable build(Location location, Name name) {
		auto s = IdentifierVisitor(&this).resolve(location, name);
		return postProcess(location, s);
	}

	Identifiable buildIn(I)(Location location, I i, Name name)
			if (isIdentifiable!I) {
		auto ii = IdentifierVisitor(&this).resolveIn(location, i, name);
		return postProcess(location, ii);
	}

	Identifiable build(TemplateInstantiation i, Expression[] fargs = []) {
		auto ti = IdentifierVisitor(&this).resolve(i, fargs);
		return postProcess(i.location, ti);
	}

	Identifiable postProcess(I)(Location location, I i) {
		return SymbolPostProcessor(&this, location).visit(i);
	}

	Identifiable finalize(I)(Location location, I i) {
		return AliasPostProcessor(&this, location).visit(i);
	}

	Identifiable resolve(Identifier i) {
		return finalize(i.location, IdentifierVisitor(&this).visit(i));
	}

	Identifiable resolveIn(I)(Location location, I i, Name name)
			if (isIdentifiable!I) {
		return finalize(location,
		                IdentifierVisitor(&this).resolveIn(location, i, name));
	}

private:
	Expression wrap(Location location, Expression e) {
		if (thisExpr is null) {
			return e;
		}

		import d.ir.expression : build;
		return build!BinaryExpression(location, e.type, BinaryOp.Comma,
		                              getThis(location), e);
	}

	void setThis(Expression thisExpr) in(this.thisExpr is null) {
		this.thisExpr = thisExpr;
	}

	Expression acquireThis() {
		// Make sure we don't consume this twice.
		scope(exit) thisExpr = null;
		return thisExpr;
	}

	Expression getThis(Location location) {
		if (thisExpr) {
			return acquireThis();
		}

		import d.semantic.expression;
		return ExpressionVisitor(pass).getThis(location);
	}
}

// XXX: probably a "feature" this can't be passed as alias this if private.
Identifiable identifiableHandler(T)(T t) {
	return Identifiable(t);
}

private:

enum isIdentifiable(T) = is(T : Expression) || is(T : Type) || is(T : Symbol)
	|| is(T : Identifiable);

alias IdentifierPass = IdentifierResolver*;

struct IdentifierVisitor {
private:
	IdentifierPass pass;
	alias pass this;

	this(IdentifierPass pass) {
		this.pass = pass;
	}

public:
	Identifiable visit(Identifier i) {
		return this.dispatch(i);
	}

	Identifiable visit(BasicIdentifier i) {
		return Identifiable(resolve(i.location, i.name));
	}

	Identifiable visit(IdentifierDotIdentifier i) {
		return resolveIn(i.location, visit(i.identifier), i.name);
	}

	Identifiable visit(TemplateInstantiation i) {
		return resolve(i);
	}

	Identifiable visit(DotIdentifier i) {
		return resolveIn(i.location, currentScope.getModule(), i.name);
	}

	Identifiable visit(ExpressionDotIdentifier i) {
		import d.semantic.expression;
		auto e = ExpressionVisitor(pass.pass).visit(i.expression);
		return resolveIn(i.location, e, i.name);
	}

	Identifiable visit(TypeDotIdentifier i) {
		import d.semantic.type;
		auto t = TypeVisitor(pass.pass).visit(i.type);
		return resolveIn(i.location, t, i.name);
	}

	Identifiable visit(IdentifierBracketIdentifier i) {
		return resolveBracket(i.location, i.indexed, i.index);
	}

	Identifiable visit(IdentifierBracketExpression i) {
		import d.semantic.expression;
		auto e = ExpressionVisitor(pass.pass).visit(i.index);
		return resolveBracket(i.location, i.indexed, e);
	}

private:
	Symbol resolve(Location location, Name name) {
		auto symbol = currentScope.search(location, name);

		// I wish we had ?:
		return symbol ? symbol : resolveImport(location, name);
	}

	Identifiable resolveIn(Location location, Identifiable i, Name name) {
		return i.apply!(ii => resolveIn(location, ii, name))();
	}

	Identifiable resolveIn(Location location, Expression e, Name name) {
		return ExpressionDotIdentifierResolver(pass, location, name).visit(e);
	}

	Identifiable resolveIn(Location location, Type t, Name name) {
		return TypeDotIdentifierResolver(pass, location, name).visit(t);
	}

	Identifiable resolveIn(Location location, Symbol s, Name name) {
		return SymbolDotIdentifierResolver(pass, location, name).visit(s);
	}

	Symbol resolveImport(Location location, Name name) {
		auto dscope = currentScope;

		while (true) {
			Symbol symbol;

			foreach (m; dscope.getImports()) {
				scheduler.require(m, Step.Populated);

				auto symInMod = m.resolve(location, name);
				if (symInMod) {
					if (symbol) {
						return new CompileError(
							location,
							"Ambiguous symbol " ~ name.toString(context)
						).symbol;
					}

					symbol = symInMod;
				}
			}

			if (symbol) {
				return symbol;
			}

			dscope = dscope.getParentScope();
			if (dscope is null) {
				return new CompileError(
					location,
					"Symbol " ~ name.toString(context) ~ " has not been found"
				).symbol;
			}

			if (auto sscope = cast(Symbol) dscope) {
				scheduler.require(sscope, Step.Populated);
			}
		}
	}

	Identifiable resolve(TemplateInstantiation i, Expression[] fargs = [])
			// We don't want to resolve arguments with the same context we have here.
			in(acquireThis() is null) {
		alias astapply = d.ast.identifier.apply;

		import d.semantic.dtemplate : TemplateInstancier;
		import d.ast.type : AstType;
		import std.algorithm, std.array;
		auto args = i.arguments.map!(a => astapply!((a) {
			alias T = typeof(a);
			static if (is(T : Identifier)) {
				assert(pass.acquireThis() is null);

				return visit(a).apply!((val) {
					static if (is(typeof(val) : Expression)) {
						return TemplateArgument(evaluate(val));
					} else {
						return TemplateArgument(val);
					}
				})();
			} else static if (is(T : AstType)) {
				import d.semantic.type;
				return TemplateArgument(TypeVisitor(pass.pass).visit(a));
			} else {
				import d.semantic.expression;
				auto e = ExpressionVisitor(pass.pass).visit(a);
				return TemplateArgument(evaluate(e));
			}
		})(a)).array();

		CompileError ce;
		Symbol instantiated;

		auto iloc = i.location;
		auto instance = finalize(
			i.identifier.location,
			visit(i.identifier)
		).apply!(delegate TemplateInstance(identified) {
			static if (is(typeof(identified) : Symbol)) {
				// If we are within a pattern, we are not looking to instanciate.
				// XXX: Arguably, we'd like the TemplateInstancier to figure out if
				// this is a pattern instead of using this hack.
				if (inPattern) {
					instantiated = identified;
					return null;
				}

				if (auto s = cast(OverloadSet) identified) {
					return TemplateInstancier(pass.pass)
						.instanciate(iloc, s, args, fargs);
				}

				if (auto t = cast(Template) identified) {
					return TemplateInstancier(pass.pass)
						.instanciate(iloc, t, args, fargs);
				}
			}

			ce = getError(identified, iloc,
			              "Unexpected " ~ typeid(identified).toString());

			return null;
		})();

		if (inPattern && instantiated) {
			return Identifiable(Pattern(instantiated, args).getType());
		}

		if (instance is null) {
			assert(ce, "No error reported :(");
			return Identifiable(ce.symbol);
		}

		return Identifiable(instance);
	}

	Identifiable resolveBracket(I)(Location location, Identifier base,
	                               I index) {
		// XXX: dafuq alias this :/
		return
			pass.build(base).apply!(i => resolveBracket(location, i, index))();
	}

	Identifiable resolveBracket(B)(Location location, B base, Identifier index)
			if (!is(B : Identifier)) {
		// We don't want to use the same this for base and index.
		auto oldThisExpr = acquireThis();
		scope(exit) setThis(oldThisExpr);

		// XXX: dafuq alias this :/
		return
			pass.build(index).apply!(i => resolveBracket(location, base, i))();
	}

	Identifiable resolveBracket(Location location, Expression base,
	                            Expression index) {
		import d.semantic.expression;
		auto e = ExpressionVisitor(pass.pass).getIndex(location, base, index);
		return Identifiable(e);
	}

	Identifiable resolveBracket(Location location, Type base,
	                            Expression index) {
		import d.semantic.caster, d.semantic.expression;
		auto size = evalIntegral(
			buildImplicitCast(pass.pass, index.location,
			                  pass.object.getSizeT().type, index));

		assert(size <= uint.max,
		       "Array larger than uint.max are not supported");

		return Identifiable(base.getArray(cast(uint) size));
	}

	Identifiable resolveBracket(Location location, Type base, Type index) {
		assert(0, "Maps not implemented");
	}

	Identifiable resolveBracket(Location location, Expression base,
	                            Type index) {
		assert(0, "Wat wat wat ?");
	}

	Identifiable resolveBracket(S1, S2)(Location location, S1 base, S2 index)
			if ((is(S1 : Symbol) || is(S2 : Symbol))
				    && !(is(S1 : Identifier) || is(S2 : Identifier))) {
		assert(0, "Wat wat wat ?");
	}
}

public auto isError(Identifiable i) {
	return i.apply!((identified) {
		alias T = typeof(identified);
		static if (is(T : Symbol)) {
			return typeid(identified) is typeid(ErrorSymbol);
		} else static if (is(T : Expression)) {
			return typeid(identified) is typeid(ErrorExpression);
		} else static if (is(T : Type)) {
			return identified.kind == TypeKind.Error;
		} else {
			static assert(0, "Dafuq ?");
		}
	})();
}

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

alias SymbolPostProcessor = IdentifierPostProcessor!false;
alias AliasPostProcessor = IdentifierPostProcessor!true;

struct IdentifierPostProcessor(bool asAlias) {
	IdentifierPass pass;
	alias pass this;

	Location location;

	this(IdentifierPass pass, Location location) {
		this.pass = pass;
		this.location = location;
	}

	Identifiable visit(Identifiable i) {
		return i.apply!(ii => visit(ii))();
	}

	Identifiable visit(Expression e) {
		return Identifiable(wrap(location, e));
	}

	Identifiable visit(Type t) {
		return Identifiable(t);
	}

	Identifiable visit(Symbol s) {
		return this.dispatch(s);
	}

	Identifiable visit(ValueSymbol vs) {
		return this.dispatch(vs);
	}

	Identifiable visit(Variable v) {
		if (asAlias && !thisExpr) {
			return Identifiable(v);
		}

		scheduler.require(v, Step.Signed);
		return visit(new VariableExpression(location, v));
	}

	Identifiable visit(Field f) {
		scheduler.require(f, Step.Signed);
		return
			Identifiable(build!FieldExpression(location, getThis(location), f));
	}

	Identifiable buildFun(Function f) {
		scheduler.require(f, Step.Signed);
		if (thisExpr || f.hasThis) {
			import d.semantic.expression;
			return Identifiable(ExpressionVisitor(pass.pass)
				.getFrom(location, getThis(location), f));
		}

		static if (asAlias) {
			return Identifiable(f);
		} else {
			import d.semantic.expression;
			return
				Identifiable(ExpressionVisitor(pass.pass).getFrom(location, f));
		}
	}

	Identifiable visit(Function f) {
		return buildFun(f);
	}

	Identifiable visit(Method m) {
		return buildFun(m);
	}

	Identifiable visit(OverloadSet s) {
		if (s.set.length == 1) {
			return visit(s.set[0]);
		}

		if (thisExpr is null) {
			return Identifiable(s);
		}

		auto dthis = getThis(location);

		Expression[] exprs;
		foreach (sym; s.set) {
			auto f = cast(Function) sym;
			assert(f, "Only function are implemented");

			import d.semantic.expression;
			auto e = ExpressionVisitor(pass.pass).getFrom(location, dthis, f);
			if (auto ee = cast(ErrorExpression) e) {
				continue;
			}

			exprs ~= e;
		}

		switch (exprs.length) {
			case 0:
				return Identifiable(
					new CompileError(location,
					                 "No valid candidate in overload set")
						.symbol);

			case 1:
				return Identifiable(exprs[0]);

			default:
				return Identifiable(new PolysemousExpression(location, exprs));
		}
	}

	Identifiable visit(ValueAlias a) {
		if (asAlias && !thisExpr) {
			return Identifiable(a);
		}

		scheduler.require(a, Step.Signed);
		return visit(a.value);
	}

	Identifiable visit(SymbolAlias s) {
		scheduler.require(s, Step.Populated);
		return visit(s.symbol);
	}

	private auto getSymbolType(S)(S s) {
		static if (asAlias) {
			return Identifiable(s);
		} else {
			return Identifiable(Type.get(s));
		}
	}

	Identifiable visit(TypeAlias a) {
		scheduler.require(a);
		return getSymbolType(a);
	}

	Identifiable visit(Struct s) {
		return getSymbolType(s);
	}

	Identifiable visit(Union u) {
		return getSymbolType(u);
	}

	Identifiable visit(Class c) {
		return getSymbolType(c);
	}

	Identifiable visit(Interface i) {
		return getSymbolType(i);
	}

	Identifiable visit(Enum e) {
		return getSymbolType(e);
	}

	Identifiable visit(Template t) {
		return Identifiable(t);
	}

	Identifiable visit(TemplateInstance ti) {
		static if (!asAlias) {
			scheduler.require(ti, Step.Populated);

			// Try the eponymous trick.
			Template t = ti.getTemplate();
			if (auto s = ti.resolve(location, t.name)) {
				return visit(s);
			}
		}

		return Identifiable(ti);
	}

	Identifiable visit(Module m) {
		return Identifiable(m);
	}

	Identifiable visit(TypeTemplateParameter t) {
		return getSymbolType(t);
	}

	Identifiable visit(ValueTemplateParameter v) {
		return Identifiable(v);
	}

	Identifiable visit(AliasTemplateParameter a) {
		return Identifiable(a);
	}

	Identifiable visit(ErrorSymbol e) {
		return Identifiable(e);
	}
}

/**
 * Resolve symbol.identifier.
 */
struct SymbolDotIdentifierResolver {
	IdentifierPass pass;
	alias pass this;

	Location location;
	Name name;

	this(IdentifierPass pass, Location location, Name name) {
		this.pass = pass;
		this.location = location;
		this.name = name;
	}

	Identifiable visit(Symbol s) {
		if (auto vs = cast(ValueSymbol) s) {
			return resolveIn(location, postProcess(location, vs), name);
		}

		return this.dispatch(s);
	}

	Identifiable visit(OverloadSet o) {
		auto i = postProcess(location, o);
		if (i == Identifiable(o)) {
			assert(0, "Error, infinite loop");
		}

		return resolveIn(location, i, name);
	}

	Identifiable visit(Module m) {
		scheduler.require(m, Step.Populated);
		if (auto s = m.resolve(location, name)) {
			return Identifiable(s);
		}

		return Identifiable(
			new CompileError(location,
			                 "Cannot resolve " ~ name.toString(context)).symbol
		);
	}

	Identifiable visit(TemplateInstance ti) {
		scheduler.require(ti, Step.Populated);
		if (auto s = ti.resolve(location, name)) {
			return Identifiable(s);
		}

		// This failed, let's try the eponymous trick.
		Template t = ti.getTemplate();
		if (auto s = ti.resolve(location, t.name)) {
			return resolveIn(location, s, name);
		}

		return Identifiable(
			new CompileError(location,
			                 "Cannot resolve " ~ name.toString(context)).symbol
		);
	}

	Identifiable visit(SymbolAlias s) {
		scheduler.require(s, Step.Populated);
		return visit(s.symbol);
	}

	Identifiable resolveAsType(S)(S s) {
		return TypeDotIdentifierResolver(pass, location, name).visit(s);
	}

	Identifiable visit(Struct s) {
		return resolveAsType(s);
	}

	Identifiable visit(Union u) {
		return resolveAsType(u);
	}

	Identifiable visit(Class c) {
		return resolveAsType(c);
	}

	Identifiable visit(Interface i) {
		return resolveAsType(i);
	}

	Identifiable visit(Enum e) {
		return resolveAsType(e);
	}

	Identifiable visit(TypeAlias a) {
		return resolveAsType(a);
	}

	Identifiable visit(ErrorSymbol e) {
		return Identifiable(e);
	}
}

/**
 * Resolve expression.identifier.
 */
struct ExpressionDotIdentifierResolver {
	IdentifierPass pass;
	alias pass this;

	Location location;
	Name name;

	this(IdentifierPass pass, Location location, Name name) {
		this.pass = pass;
		this.location = location;
		this.name = name;
	}

	Identifiable visit(Expression e) in(thisExpr is null) {
		e = wrap(location, e);
		return visit(e, e);
	}

	Identifiable visit(Expression e, Expression base) in(thisExpr is null) {
		auto t = e.type.getCanonical();
		if (t.isAggregate) {
			auto a = t.aggregate;

			scheduler.require(a, Step.Populated);
			if (auto sym = a.resolve(location, name)) {
				setThis(e);
				return Identifiable(sym);
			}

			if (auto c = cast(Class) a) {
				if (auto sym = lookupInBase(c)) {
					setThis(e);
					return Identifiable(sym);
				}
			}

			import d.semantic.aliasthis;
			import std.algorithm, std.array;
			auto results = AliasThisResolver!identifiableHandler(pass.pass)
				.resolve(e, a).map!((c) {
					// Make sure we process all alias this on the same base.
					auto oldThisExpr = thisExpr;
					scope(exit) thisExpr = oldThisExpr;

					auto i = resolveIn(location, c, name);

					import std.typecons;
					return tuple(i, thisExpr);
				}).filter!((t) => !t[0].isError()).array();

			if (results.length == 1) {
				thisExpr = results[0][1];
				return results[0][0];
			}

			assert(results.length == 0, "WTF am I supposed to do here ?");
		}

		auto et = t;
		while (et.kind == TypeKind.Enum) {
			scheduler.require(et.denum, Step.Populated);
			if (auto sym = et.denum.resolve(location, name)) {
				setThis(e);
				return Identifiable(sym);
			}

			et = et.denum.type.getCanonical();
		}

		// array.ptr is a special case.
		if (et.kind == TypeKind.Array && name == BuiltinName!"ptr") {
			return Identifiable(new UnaryExpression(
				location,
				t.element.getPointer(),
				UnaryOp.AddressOf,
				new IndexExpression(
					location, t.element, e,
					new IntegerLiteral(location, 0, BuiltinType.Uint))
			));
		}

		// UFCS
		if (auto ufcs = resolveUFCS(e)) {
			return Identifiable(ufcs);
		}

		if (t.kind != TypeKind.Pointer) {
			return resolveInType(base);
		}

		// Try to autodereference pointers.
		return visit(
			new UnaryExpression(e.location, t.element, UnaryOp.Dereference, e),
			base
		);
	}

	Symbol lookupInBase(Class c) {
		if (c is c.base) {
			return null;
		}

		c = c.base;
		scheduler.require(c, Step.Populated);
		if (auto sym = c.resolve(location, name)) {
			return sym;
		}

		return lookupInBase(c);
	}

	Expression resolveUFCS(Expression e) {
		// FIXME: templates and IFTI should UFCS too.
		Expression tryUFCS(Function f) {
			// No UFCS on member methods.
			if (f.hasThis) {
				return null;
			}

			import d.semantic.expression;
			auto dg = ExpressionVisitor(pass.pass).getFrom(location, e, f);
			if (typeid(dg) is typeid(ErrorExpression)) {
				return null;
			}

			return dg;
		}

		auto findUFCS(Symbol[] syms) {
			import std.algorithm, std.array;
			return syms.map!(s => cast(Function) s).filter!(f => f !is null)
			           .map!(f => tryUFCS(f)).filter!(e => e !is null).array();
		}

		// TODO: Cache this result maybe ?
		auto a = IdentifierVisitor(pass).resolve(location, name);
		if (auto os = cast(OverloadSet) a) {
			auto ufcs = findUFCS(os.set);
			if (ufcs.length > 0) {
				assert(ufcs.length == 1, "ambiguous ufcs");
				return ufcs[0];
			}
		} else if (auto f = cast(Function) a) {
			auto ufcs = tryUFCS(f);
			if (ufcs) {
				return ufcs;
			}
		}

		return null;
	}

	Identifiable resolveInType(Expression e) {
		setThis(e);
		return TypeDotIdentifierResolver(pass, location, name).visit(e.type);
	}

	Identifiable visit(ErrorExpression e) {
		return Identifiable(e.error.symbol);
	}
}

/**
 * Resolve type.identifier.
 */
struct TypeDotIdentifierResolver {
	IdentifierPass pass;
	alias pass this;

	Location location;
	Name name;

	this(IdentifierPass pass, Location location, Name name) {
		this.pass = pass;
		this.location = location;
		this.name = name;
	}

	Identifiable bailout(Type t) {
		if (name == BuiltinName!"init") {
			import d.semantic.defaultinitializer;
			return Identifiable(InitBuilder(pass.pass, location).visit(t));
		} else if (name == BuiltinName!"sizeof") {
			import d.semantic.sizeof;
			return Identifiable(
				new IntegerLiteral(location, SizeofVisitor(pass.pass).visit(t),
				                   pass.object.getSizeT().type.builtin));
		}

		return Identifiable(getError(
			t,
			location,
			name.toString(context) ~ " can't be resolved in type "
				~ t.toString(context)
		).symbol);
	}

	Identifiable visit(Type t) {
		return t.accept(this);
	}

	Identifiable visit(BuiltinType t) {
		if (name == BuiltinName!"max") {
			if (t == BuiltinType.Bool) {
				return Identifiable(new BooleanLiteral(location, true));
			} else if (isIntegral(t)) {
				return Identifiable(new IntegerLiteral(location, getMax(t), t));
			} else if (isChar(t)) {
				auto c = new CharacterLiteral(location, getCharMax(t), t);
				return Identifiable(c);
			}
		} else if (name == BuiltinName!"min") {
			if (t == BuiltinType.Bool) {
				return Identifiable(new BooleanLiteral(location, false));
			} else if (isIntegral(t)) {
				return Identifiable(new IntegerLiteral(location, getMin(t), t));
			} else if (isChar(t)) {
				return Identifiable(new CharacterLiteral(location, '\0', t));
			}
		}

		return bailout(Type.get(t));
	}

	Identifiable visitPointerOf(Type t) {
		return bailout(t.getPointer());
	}

	Identifiable visitSliceOf(Type t) {
		// Slice have magic fields.
		// XXX: This would gain to be moved to object.d
		if (name == BuiltinName!"length") {
			// FIXME: pass explicit location.
			auto location = Location.init;
			auto s = new Field(location, 0, pass.object.getSizeT().type,
			                   BuiltinName!"length", null);

			s.step = Step.Processed;
			return Identifiable(s);
		}

		if (name == BuiltinName!"ptr") {
			// FIXME: pass explicit location.
			auto location = Location.init;
			auto s =
				new Field(location, 1, t.getPointer(), BuiltinName!"ptr", null);

			s.step = Step.Processed;
			return Identifiable(s);
		}

		return bailout(t.getSlice());
	}

	Identifiable visitArrayOf(uint size, Type t) {
		if (name != BuiltinName!"length") {
			return bailout(t.getArray(size));
		}

		return Identifiable(
			new IntegerLiteral(location, size,
			                   pass.object.getSizeT().type.builtin));
	}

	Symbol resolveInAggregate(Aggregate a) {
		scheduler.require(a, Step.Populated);
		return a.resolve(location, name);
	}

	Identifiable visit(Struct s) {
		if (auto sym = resolveInAggregate(s)) {
			return Identifiable(sym);
		}

		return bailout(Type.get(s));
	}

	Identifiable visit(Union u) {
		if (auto sym = resolveInAggregate(u)) {
			return Identifiable(sym);
		}

		return bailout(Type.get(u));
	}

	Identifiable visit(Class c) {
		if (auto s = resolveInAggregate(c)) {
			return Identifiable(s);
		}

		if (c !is c.base) {
			return visit(c.base);
		}

		return bailout(Type.get(c));
	}

	Identifiable visit(Interface i) {
		assert(0, "Not Implemented.");
	}

	Identifiable visit(Enum e) {
		scheduler.require(e, Step.Populated);
		if (auto s = e.resolve(location, name)) {
			return Identifiable(s);
		}

		return visit(e.type);
	}

	Identifiable visit(TypeAlias a) {
		scheduler.require(a, Step.Populated);
		return visit(a.type);
	}

	Identifiable visit(Function f) {
		assert(0, "Not Implemented.");
	}

	Identifiable visit(Type[] seq) {
		assert(0, "Not Implemented.");
	}

	Identifiable visit(FunctionType f) {
		return bailout(f.getType());
	}

	Identifiable visit(Pattern p) {
		return Identifiable(
			new CompileError(location, "Cannot resolve identifier on pattern.")
				.symbol);
	}

	Identifiable visit(CompileError e) {
		return Identifiable(e.symbol);
	}
}
