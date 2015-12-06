module d.semantic.identifier;

import d.semantic.semantic;

import d.ast.identifier;

import d.ir.dscope;
import d.ir.error;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.context.location;
import d.context.name;

import d.exception;

alias Module = d.ir.symbol.Module;

alias SymbolResolver = IdentifierResolver!false;
alias AliasResolver  = IdentifierResolver!true;

alias TemplateSymbolResolver = TemplateDotIdentifierResolver!false;
alias TemplateAliasResolver  = TemplateDotIdentifierResolver!true;

alias SymbolPostProcessor = IdentifierPostProcessor!false;
alias AliasPostProcessor  = IdentifierPostProcessor!true;

private:

/**
 * Resolve identifier!(arguments).identifier as type or expression.
 */
struct TemplateDotIdentifierResolver(bool asAlias) {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Identifiable resolve(
		TemplateInstanciationDotIdentifier i,
		Expression[] fargs = [],
	) {
		import d.semantic.dtemplate : TemplateInstancier, TemplateArgument;
		import std.algorithm, std.array;
		auto args = i.templateInstanciation.arguments.map!((a) {
			if (auto ia = cast(IdentifierTemplateArgument) a) {
				return AliasResolver(pass)
					.visit(ia.identifier)
					.apply!((identified) {
						static if(is(typeof(identified) : Expression)) {
							return TemplateArgument(pass.evaluate(identified));
						} else {
							return TemplateArgument(identified);
						}
					})();
			} else if (auto ta = cast(TypeTemplateArgument) a) {
				import d.semantic.type;
				return TemplateArgument(TypeVisitor(pass).visit(ta.type));
			} else if (auto va = cast(ValueTemplateArgument) a) {
				import d.semantic.expression;
				auto e = ExpressionVisitor(pass).visit(va.value);
				return TemplateArgument(pass.evaluate(e));
			}
			
			assert(0, typeid(a).toString() ~ " is not supported.");
		}).array();
		
		CompileError ce;
		
		// XXX: identifiableHandler shouldn't be necessary,
		// we should pas a free function.
		auto instance = SymbolResolver(pass)
			.visit(i.templateInstanciation.identifier)
			.apply!(delegate TemplateInstance(identified) {
				static if (is(typeof(identified) : Symbol)) {
					if (auto t = cast(Template) identified) {
						return TemplateInstancier(pass).instanciate(
							i.templateInstanciation.location,
							t,
							args,
							fargs,
						);
					} else if (auto s = cast(OverloadSet) identified) {
						return TemplateInstancier(pass).instanciate(
							i.templateInstanciation.location,
							s,
							args,
							fargs,
						);
					}
				}
				
				ce = getError(
					identified,
					i.templateInstanciation.location,
					"Unexpected " ~ typeid(identified).toString(),
				);
				
				return null;
			})();
		
		if (instance is null) {
			assert(ce, "No error reported :(");
			return Identifiable(ce.symbol);
		}
		
		scheduler.require(instance, Step.Populated);
		
		if (auto s = instance.resolve(i.location, i.name)) {
			return IdentifierPostProcessor!asAlias(pass, i.location)
				.visit(s);
		}
		
		// Let's try eponymous trick if the previous failed.
		auto name = i.templateInstanciation.identifier.name;
		if (name != i.name) {
			if (auto s = instance.resolve(i.location, name)) {
				return IdentifierResolver!asAlias(pass)
					.resolveInSymbol(i.location, s, i.name);
			}
		}
		
		return Identifiable(new CompileError(
			i.location,
			i.name.toString(context) ~ " not found in template").symbol,
		);
	}
}

alias Identifiable = Type.UnionType!(Symbol, Expression);

public auto apply(alias handler)(Identifiable i) {
	alias Tag = typeof(i.tag);
	final switch(i.tag) with(Tag) {
		case Symbol :
			return handler(i.get!Symbol);
		
		case Expression :
			return handler(i.get!Expression);
		
		case Type :
			return handler(i.get!Type);
	}
}

// XXX: probably a "feature" this can't be passed as alias this if private.
public Identifiable identifiableHandler(T)(T t) {
	return Identifiable(t);
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

/**
 * General entry point to resolve identifiers.
 */
struct IdentifierResolver(bool asAlias) {
	private SemanticPass pass;
	alias pass this;
	
	alias SelfPostProcessor = IdentifierPostProcessor!asAlias;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Identifiable visit(Identifier i) {
		return this.dispatch(i);
	}
	
	private Symbol resolveImportedSymbol(Location location, Name name) {
		auto dscope = currentScope;
		
		while(true) {
			Symbol symbol;
			
			foreach(m; dscope.getImports()) {
				scheduler.require(m, Step.Populated);
				
				auto symInMod = m.resolve(location, name);
				if (symInMod) {
					if (symbol) {
						return new CompileError(
							location,
							"Ambiguous symbol " ~ name.toString(context),
						).symbol;
					}
					
					symbol = symInMod;
				}
			}
			
			if (symbol) return symbol;
			
			dscope = dscope.getParentScope();
			if (dscope is null) {
				return new CompileError(
					location,
					"Symbol " ~ name.toString(context) ~ " has not been found",
				).symbol;
			}
			
			if (auto sscope = cast(Symbol) dscope) {
				scheduler.require(sscope, Step.Populated);
			}
		}
	}
	
	private Symbol resolveSymbolByName(Location location, Name name) {
		auto symbol = currentScope.search(location, name);
		
		// I wish we had ?:
		return symbol ? symbol : resolveImportedSymbol(location, name);
	}
	
	Identifiable resolveName(Location location, Name name) {
		return SelfPostProcessor(pass, location)
			.visit(resolveSymbolByName(location, name));
	}
	
	Identifiable visit(BasicIdentifier i) {
		return resolveName(i.location, i.name);
	}
	
	Identifiable visit(IdentifierDotIdentifier i) {
		auto base = SymbolResolver(pass).visit(i.identifier);
		return resolveInIdentifiable(i.location, base, i.name);
	}
	
	Identifiable visit(DotIdentifier i) {
		return resolveInSymbol(i.location, currentScope.getModule(), i.name);
	}
	
	Identifiable postProcess(Location location, Symbol s) {
		return SelfPostProcessor(pass, location).visit(s);
	}
	
	Identifiable postProcess(Location location, Expression e) {
		return Identifiable(e);
	}
	
	Identifiable postProcess(Location location, Type t) {
		return Identifiable(t);
	}
	
	Identifiable resolveInType(Location location, Type t, Name name) {
		return TypeDotIdentifierResolver(pass, location, name)
			.visit(t)
			.apply!(i => postProcess(location, i))();
	}
	
	Identifiable resolveInExpression(
		Location location,
		Expression expr,
		Name name,
	) {
		return ExpressionDotIdentifierResolver(pass, location, expr, name)
			.resolve()
			.apply!(i => postProcess(location, i))();
	}
	
	// XXX: higly dubious, see how this can be removed.
	Identifiable resolveInSymbol(Location location, Symbol s, Name name) {
		return resolveInIdentifiable(
			location,
			SymbolPostProcessor(pass, location).visit(s),
			name,
		);
	}
	
	private Identifiable resolveInIdentifiable(
		Location location,
		Identifiable i,
		Name name,
	) {
		return i.apply!(delegate Identifiable(identified) {
			alias T = typeof(identified);
			static if (is(T : Type)) {
				return resolveInType(location, identified, name);
			} else static if (is(T : Expression)) {
				return resolveInExpression(location, identified, name);
			} else {
				pass.scheduler.require(identified, pass.Step.Populated);
				
				Symbol s;
				if (auto i = cast(TemplateInstance) identified) {
					s = i.resolve(location, name);
				} else if (auto m = cast(Module) identified) {
					s = m.resolve(location, name);
				}
				
				if (s is null) {
					s = getError(
						identified,
						location,
						"Can't resolve " ~ name.toString(pass.context),
					).symbol;
				}
				
				return SelfPostProcessor(pass, location).visit(s);
			}
		})();
	}
	
	Identifiable visit(ExpressionDotIdentifier i) {
		import d.semantic.expression;
		return resolveInExpression(
			i.location,
			ExpressionVisitor(pass).visit(i.expression),
			i.name,
		);
	}
	
	Identifiable visit(TypeDotIdentifier i) {
		import d.semantic.type;
		return resolveInType(
			i.location,
			TypeVisitor(pass).visit(i.type),
			i.name,
		);
	}
	
	Identifiable visit(TemplateInstanciationDotIdentifier i) {
		return TemplateDotIdentifierResolver!asAlias(pass).resolve(i);
	}
	
	private Identifiable resolveTypeBracketIdentifier(
		Location location,
		Type indexed,
		Identifier index,
	) {
		return SymbolResolver(pass)
			.visit(index)
			.apply!(delegate Identifiable(identified) {
				alias U = typeof(identified);
				static if (is(U : Type)) {
					assert(0, "AA are not implemented");
				} else static if (is(U : Expression)) {
					return resolveTypeBracketExpression(
						location,
						indexed,
						identified,
					);
				} else {
					assert(0, "Add meaningful error message.");
				}
			})();
	}
	
	private Identifiable resolveTypeBracketExpression(
		Location location,
		Type indexed,
		Expression index,
	) {
		import d.semantic.caster, d.semantic.expression;
		auto size = pass.evalIntegral(buildImplicitCast(
			pass,
			index.location,
			pass.object.getSizeT().type,
			index,
		));
		
		assert(
			size <= uint.max,
			"Array larger than uint.max are not supported"
		);
		
		return Identifiable(indexed.getArray(cast(uint) size));
	}
	
	Identifiable visit(IdentifierBracketIdentifier i) {
		return SymbolResolver(pass)
			.visit(i.indexed)
			.apply!(delegate Identifiable(indexed) {
				alias T = typeof(indexed);
				static if (is(T : Type)) {
					return resolveTypeBracketIdentifier(
						i.location,
						indexed,
						i.index,
					);
				} else static if (is(T : Expression)) {
					return SymbolResolver(pass)
						.visit(i.index)
						.apply!(delegate Identifiable(index) {
							alias U = typeof(index);
							static if (is(U : Expression)) {
								import d.semantic.expression;
								return Identifiable(ExpressionVisitor(pass)
										.getIndex(i.location, indexed, index));
							} else {
								assert(0, "Add meaningful error message.");
							}
						})();
				} else {
					assert(0, "Add meaningful error message.");
				}
			})();
	}
	
	Identifiable visit(IdentifierBracketExpression i) {
		import d.semantic.expression;
		auto index = ExpressionVisitor(pass).visit(i.index);
		return SymbolResolver(pass)
			.visit(i.indexed)
			.apply!(delegate Identifiable(indexed) {
				alias T = typeof(indexed);
				static if (is(T : Type)) {
					return resolveTypeBracketExpression(
						i.location,
						indexed,
						index,
					);
				} else static if (is(T : Expression)) {
					return Identifiable(ExpressionVisitor(pass)
						.getIndex(i.location, indexed, index));
				} else {
					assert(0, "It seems some weird index expression");
				}
			})();
	}
}

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

/**
 * Post process resolved identifiers.
 */
struct IdentifierPostProcessor(bool asAlias) {
	private SemanticPass pass;
	alias pass this;
	
	private Location location;
	
	this(SemanticPass pass, Location location) {
		this.pass = pass;
		this.location = location;
	}
	
	Identifiable visit(Symbol s) {
		return this.dispatch(s);
	}
	
	Identifiable visit(TypeSymbol s) {
		return this.dispatch(s);
	}
	
	Identifiable visit(ValueSymbol s) {
		return this.dispatch(s);
	}
	
	Identifiable visit(Function f) {
		static if (asAlias) {
			return Identifiable(f);
		} else {
			import d.semantic.expression;
			return Identifiable(ExpressionVisitor(pass).getFrom(location, f));
		}
	}
	
	Identifiable visit(Method m) {
		return visit(cast(Function) m);
	}
	
	Identifiable visit(Variable v) {
		static if (asAlias) {
			return Identifiable(v);
		} else {
			scheduler.require(v, Step.Signed);
			return Identifiable(new VariableExpression(location, v));
		}
	}
	
	Identifiable visit(Field f) {
		scheduler.require(f, Step.Signed);
		
		import d.semantic.expression;
		auto thisExpr = ExpressionVisitor(pass).getThis(location);
		return Identifiable(build!FieldExpression(location, thisExpr, f));
	}
	
	Identifiable visit(ValueAlias a) {
		static if (asAlias) {
			return Identifiable(a);
		} else {
			scheduler.require(a, Step.Signed);
			return Identifiable(a.value);
		}
	}
	
	Identifiable visit(OverloadSet s) {
		if (s.set.length == 1) {
			return visit(s.set[0]);
		}
		
		return Identifiable(s);
	}
	
	Identifiable visit(SymbolAlias s) {
		scheduler.require(s, Step.Signed);
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
	
	Identifiable visit(TemplateInstance i) {
		return Identifiable(i);
	}
	
	Identifiable visit(Module m) {
		return Identifiable(m);
	}
	
	Identifiable visit(TypeTemplateParameter t) {
		return getSymbolType(t);
	}
	
	Identifiable visit(ErrorSymbol e) {
		return Identifiable(e);
	}
}

/**
 * Resolve expression.identifier as type or expression.
 */
struct ExpressionDotIdentifierResolver {
	SemanticPass pass;
	alias pass this;
	
	Location location;
	Expression expr;
	Name name;
	
	this(SemanticPass pass, Location location, Expression expr, Name name) {
		this.pass = pass;
		this.location = location;
		this.expr = expr;
		this.name = name;
	}
	
	Identifiable resolve() {
		return resolve(expr);
	}
	
	Identifiable resolve(Expression base) {
		auto t = expr.type.getCanonical();
		if (t.isAggregate) {
			auto a = t.aggregate;
			
			scheduler.require(a, Step.Populated);
			if (auto sym = a.resolve(location, name)) {
				return visit(sym);
			}
			
			if (auto c = cast(Class) a) {
				if (auto sym = lookupInBase(c)) {
					return visit(sym);
				}
			}
			
			import d.semantic.aliasthis;
			import std.algorithm, std.array;
			auto results = AliasThisResolver!identifiableHandler(pass)
				.resolve(expr, a)
				.map!(c => SymbolResolver(pass)
						.resolveInIdentifiable(location, c, name))
				.filter!(i => !i.isError())
				.array();
			
			if (results.length == 1) {
				return results[0];
			} else if (results.length > 1) {
				assert(0, "WTF am I supposed to do here ?");
			}
		}
		
		auto et = t;
		while (et.kind == TypeKind.Enum) {
			scheduler.require(et.denum, Step.Populated);
			if (auto sym = et.denum.resolve(location, name)) {
				return visit(sym);
			}
			
			et = et.denum.type.getCanonical();
		}
		
		// UFCS
		if (auto ufcs = resolveUFCS()) {
			return Identifiable(ufcs);
		}
		
		// Try to autodereference pointers.
		if (t.kind == TypeKind.Pointer) {
			expr = new UnaryExpression(
				expr.location,
				t.element,
				UnaryOp.Dereference,
				expr,
			);
			
			return resolve(base);
		}
		
		return resolveInType(base);
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
	
	Expression resolveUFCS() {
		// FIXME: templates and IFTI should UFCS too.
		Expression tryUFCS(Function f) {
			// No UFCS on member methods.
			if (f.hasThis) {
				return null;
			}
			
			import d.semantic.expression;
			auto e = ExpressionVisitor(pass).getFrom(location, expr, f);
			if (typeid(e) is typeid(ErrorExpression)) {
				return null;
			}
			
			return e;
		}
		
		auto findUFCS(Symbol[] syms) {
			import std.algorithm, std.array;
			return syms
				.map!(s => cast(Function) s)
				.filter!(f => f !is null)
				.map!(f => tryUFCS(f))
				.filter!(e => e !is null)
				.array();
		}
		
		// TODO: Cache this result maybe ?
		auto a = AliasResolver(pass)
			.resolveSymbolByName(location, name);
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
	
	Identifiable resolveInType(Expression base) {
		return TypeDotIdentifierResolver(pass, location, name)
			.visit(base.type)
			.apply!(delegate Identifiable(identified) {
				return ContextIdentifierPostProcessor(
					pass,
					location,
					base,
				).visit(identified);
			})();
	}
	
	Identifiable visit(Symbol s) {
		return ContextIdentifierPostProcessor(pass, location, expr)
			.visit(s);
	}
}

struct ContextIdentifierPostProcessor {
	SemanticPass pass;
	alias pass this;
	
	Location location;
	Expression base;
	
	this(SemanticPass pass, Location location, Expression base) {
		this.pass = pass;
		this.location = location;
		this.base = base;
	}
	
	Identifiable visit(Expression e) {
		return Identifiable(build!BinaryExpression(
			location,
			e.type,
			BinaryOp.Comma,
			base,
			e,
		));
	}
	
	Identifiable visit(Type t) {
		if (t.kind == TypeKind.Error) {
			return Identifiable(t);
		}
		
		assert(0, "expression.type not implemented");
	}
	
	Identifiable visit(Symbol s) {
		return this.dispatch!((s) {
			throw new CompileException(
				s.location,
				"Don't know how to dispatch " ~ typeid(s).toString(),
			);
		})(s);
	}
	
	Identifiable visit(OverloadSet s) {
		if (s.set.length == 1) {
			return visit(s.set[0]);
		}
		
		Expression[] exprs;
		foreach (sym; s.set) {
			if (auto f = cast(Function) sym) {
				auto e = makeExpression(f);
				if (auto ee = cast(ErrorExpression) e) {
					continue;
				}
				
				exprs ~= e;
			} else {
				assert(0, "not implemented: template with context");
			}
		}
		
		switch(exprs.length) {
			case 0 :
				return Identifiable(new CompileError(
					location,
					"No valid candidate in overload set").symbol,
				);
			
			case 1 :
				return Identifiable(exprs[0]);
			
			default :
				return Identifiable(new PolysemousExpression(location, exprs));
		}
	}
	
	Identifiable visit(Field f) {
		scheduler.require(f, Step.Signed);
		return Identifiable(new FieldExpression(location, base, f));
	}
	
	private Expression makeExpression(Function f) {
		import d.semantic.expression;
		return ExpressionVisitor(pass).getFrom(location, base, f);
	}
	
	Identifiable visit(Function f) {
		return Identifiable(makeExpression(f));
	}
	
	Identifiable visit(Method m) {
		return Identifiable(makeExpression(m));
	}
	
	Identifiable visit(TypeAlias a) {
		// XXX: get rid of peelAlias and then get rid of this.
		scheduler.require(a);
		return Identifiable(a);
	}
	
	Identifiable visit(Struct s) {
		return Identifiable(s);
	}
	
	Identifiable visit(Class c) {
		return Identifiable(c);
	}
	
	Identifiable visit(Enum e) {
		return Identifiable(e);
	}
	
	Identifiable visit(ErrorSymbol e) {
		return Identifiable(e);
	}
}

/**
 * Resolve symbols in types.
 */
struct TypeDotIdentifierResolver {
	SemanticPass pass;
	alias pass this;
	
	Location location;
	Name name;
	
	this(SemanticPass pass, Location location, Name name) {
		this.pass = pass;
		this.location = location;
		this.name = name;
	}
	
	Identifiable bailout(Type t) {
		if (name == BuiltinName!"init") {
			import d.semantic.defaultinitializer;
			return Identifiable(InitBuilder(pass, location).visit(t));
		} else if (name == BuiltinName!"sizeof") {
			import d.semantic.sizeof;
			return Identifiable(new IntegerLiteral(
				location,
				SizeofVisitor(pass).visit(t),
				pass.object.getSizeT().type.builtin,
			));
		}
		
		return Identifiable(getError(
			t,
			location,
			name.toString(context)
				~ " can't be resolved in type "
				~ t.toString(context),
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
			auto s = new Field(
				location,
				0,
				pass.object.getSizeT().type,
				BuiltinName!"length",
				null,
			);
			
			s.step = Step.Processed;
			return Identifiable(s);
		} else if (name == BuiltinName!"ptr") {
			// FIXME: pass explicit location.
			auto location = Location.init;
			auto s = new Field(
				location,
				1,
				t.getPointer(),
				BuiltinName!"ptr",
				null,
			);
			
			s.step = Step.Processed;
			return Identifiable(s);
		}
		
		return bailout(t.getSlice());
	}
	
	Identifiable visitArrayOf(uint size, Type t) {
		if (name != BuiltinName!"length") {
			return bailout(t.getArray(size));
		}
		
		return Identifiable(new IntegerLiteral(
			location,
			size,
			pass.object.getSizeT().type.builtin,
		));
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
	
	Identifiable visit(TypeTemplateParameter t) {
		assert(0, "Can't resolve identifier on template type.");
	}
	
	Identifiable visit(CompileError e) {
		return Identifiable(e.symbol);
	}
}
