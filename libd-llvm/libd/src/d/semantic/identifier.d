module d.semantic.identifier;

import d.semantic.semantic;

import d.ast.dmodule;
import d.ast.identifier;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.context;
import d.exception;
import d.location;

import std.algorithm;
import std.array;

alias Module = d.ir.symbol.Module;

// TODO: specify if symbol must be packed into type/expression or not.
struct IdentifierVisitor(alias handler, bool asAlias = false) {
	private SemanticPass pass;
	alias pass this;
	
	alias Ret = typeof(handler(null));
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Ret visit(Identifier i) {
		return this.dispatch(i);
	}
	
	private Symbol resolveImportedSymbol(Location location, Name name) {
		auto dscope = currentScope;
		
		while(true) {
			Symbol symbol;
			
			foreach(m; dscope.imports) {
				scheduler.require(m, Step.Populated);
				
				auto symInMod = m.dscope.resolve(name);
				if(symInMod) {
					if(symbol) {
						return pass.raiseCondition!Symbol(location, "Ambiguous symbol " ~ name.toString(context) ~ ".");
					}
					
					symbol = symInMod;
				}
			}
			
			if(symbol) return symbol;
			
			if(auto nested = cast(NestedScope) dscope) {
				dscope = nested.parent;
			} else {
				return pass.raiseCondition!Symbol(location, "Symbol " ~ name.toString(context) ~ " has not been found.");
			}
			
			if(auto sscope = cast(SymbolScope) dscope) {
				scheduler.require(sscope.symbol, Step.Populated);
			}
		}
	}
	
	private Symbol resolveName(Location location, Name name) {
		auto symbol = currentScope.search(name);
		
		// I wish we had ?:
		return symbol ? symbol : resolveImportedSymbol(location, name);
	}
	
	Ret visit(BasicIdentifier i) {
		return visit(i.location, resolveName(i.location, i.name));
	}
	
	Ret visit(IdentifierDotIdentifier i) {
		return resolveInIdentifiable(i.location, IdentifierVisitor!identifiableHandler(pass).visit(i.identifier), i.name);
	}
	
	Ret resolveInSymbol(Location location, Symbol s, Name name) {
		return resolveInIdentifiable(location, IdentifierVisitor!identifiableHandler(pass).visit(location, s), name);
	}
	
	Ret resolveInType(Location location, QualType t, Name name) {
		if(Symbol s = SymbolInTypeResolver(pass).visit(name, t)) {
			return visit(location, s);
		}
		
		if(name == BuiltinName!"init") {
			assert(0, "init, yeah sure . . .");
		} else if(name == BuiltinName!"sizeof") {
			import d.semantic.sizeof;
			auto sv = SizeofVisitor(pass);
			return handler(new IntegerLiteral!false(location, sv.visit(t), TypeKind.Uint));
		}
		
		throw new CompileException(location, name.toString(context) ~ " can't be resolved in type " ~ t.toString(context));
	}
	
	Ret resolveInExpression(Location location, Expression e, Name name) {
		return ExpressionDotIdentifierVisitor!handler(pass).visit(location, name, e);
	}
	
	private Ret resolveInIdentifiable(Location location, Identifiable i, Name name) {
		return i.apply!(delegate Ret(identified) {
			static if(is(typeof(identified) : QualType)) {
				return resolveInType(location, identified, name);
			} else static if(is(typeof(identified) : Expression)) {
				return resolveInExpression(location, identified, name);
			} else {
				pass.scheduler.require(identified, pass.Step.Populated);
				
				if(auto i = cast(TemplateInstance) identified) {
					return visit(location, i.dscope.resolve(name));
				} else if(auto m = cast(Module) identified) {
					return visit(location, m.dscope.resolve(name));
				}
				
				throw new CompileException(location, "Can't resolve " ~ name.toString(pass.context));
			}
		})();
	}
	
	Ret visit(ExpressionDotIdentifier i) {
		return ExpressionDotIdentifierVisitor!handler(pass).visit(i);
	}
	
	Ret visit(TypeDotIdentifier i) {
		import d.semantic.type;
		auto tv = TypeVisitor(pass);
		return resolveInType(i.location, tv.visit(i.type), i.name);
	}
	
	Ret visit(TemplateInstanciationDotIdentifier i) {
		return TemplateDotIdentifierVisitor!handler(pass).resolve(i);
	}
	
	Ret visit(IdentifierBracketIdentifier i) {
		assert(0, "Not implemented");
	}
	
	Ret visit(IdentifierBracketExpression i) {
		return IdentifierVisitor!identifiableHandler(pass).visit(i.indexed).apply!(delegate Ret(identified) {
			// TODO: deduplicate code form type and expression visitor.
			static if(is(typeof(identified) : QualType)) {
				import d.semantic.caster, d.semantic.expression;
				auto ev = ExpressionVisitor(pass);
				auto se = buildImplicitCast(pass, i.index.location, getBuiltin(TypeKind.Ulong), ev.visit(i.index));
				auto size = (cast(IntegerLiteral!false) pass.evaluate(se)).value;
				
				return handler(QualType(new ArrayType(identified, size)));
			} else static if(is(typeof(identified) : Expression)) {
				auto qt = peelAlias(identified.type);
				auto type = qt.type;
				if(auto asSlice = cast(SliceType) type) {
					qt = asSlice.sliced;
				} else if(auto asPointer = cast(PointerType) type) {
					qt = asPointer.pointed;
				} else if(auto asArray = cast(ArrayType) type) {
					qt = asArray.elementType;
				} else {
					return handler(pass.raiseCondition!Expression(i.location, "Can't index " ~ identified.type.toString(pass.context)));
				}
				
				import d.semantic.expression;
				auto ev = ExpressionVisitor(pass);
				return handler(new IndexExpression(i.location, qt, identified, [ev.visit(i.index)]));
			} else {
				assert(0, "WTF ???");
			}
		})();
	}
	
	Ret visit(Location location, Symbol s) {
		return this.dispatch(location, s);
	}
	
	Ret visit(Location location, TypeSymbol s) {
		return this.dispatch(location, s);
	}
	
	private auto getSymbolExpression(Location location, ValueSymbol s) {
		static if(asAlias) {
			return handler(s);
		} else {
			scheduler.require(s, Step.Signed);
			return handler(new SymbolExpression(location, s));
		}
	}
	
	Ret visit(Location location, Function f) {
		static if(asAlias) {
			return handler(f);
		} else {
			import d.semantic.expression;
			auto ev = ExpressionVisitor(pass);
			return handler(ev.getFrom(location, f));
		}
	}
	
	Ret visit(Location location, Parameter p) {
		return getSymbolExpression(location, p);
	}
	
	Ret visit(Location location, Variable v) {
		return getSymbolExpression(location, v);
	}
	
	Ret visit(Location location, Field f) {
		scheduler.require(f, Step.Signed);
		return handler(new FieldExpression(location, new ThisExpression(location, QualType(thisType.type)), f));
	}
	
	Ret visit(Location location, OverloadSet s) {
		if(s.set.length == 1) {
			return visit(location, s.set[0]);
		}
		
		return handler(s);
	}
	
	private auto getSymbolType(T, S)(S s) {
		static if(asAlias) {
			return handler(s);
		} else {
			return handler(QualType(new T(s)));
		}
	}
	
	Ret visit(Location location, TypeAlias a) {
		// XXX: get rid of peelAlias and then get rid of this.
		scheduler.require(a);
		return getSymbolType!AliasType(a);
	}
	
	Ret visit(Location location, Struct s) {
		return getSymbolType!StructType(s);
	}
	
	Ret visit(Location location, Class c) {
		return getSymbolType!ClassType(c);
	}
	
	Ret visit(Location location, Enum e) {
		return getSymbolType!EnumType(e);
	}
	
	Ret visit(Location location, Template t) {
		return handler(t);
	}
	
	Ret visit(Location location, TemplateInstance i) {
		return handler(i);
	}
	
	Ret visit(Location location, Module m) {
		return handler(m);
	}
	
	Ret visit(Location location, TypeTemplateParameter t) {
		import d.ir.dtemplate;
		return getSymbolType!TemplatedType(t);
	}
}

/**
 * Resolve identifier!(arguments).identifier as type or expression.
 */
struct TemplateDotIdentifierVisitor(alias handler) {
	private SemanticPass pass;
	alias pass this;
	
	alias Ret = typeof(handler(null));
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Ret resolve(TemplateInstanciationDotIdentifier i, Expression[] fargs = []) {
		import d.semantic.dtemplate : TemplateInstancier, TemplateArgument, argHandler;
		auto iva = IdentifierVisitor!(argHandler, true)(pass);
		auto args = i.templateInstanciation.arguments.map!((a) {
			if(auto ta = cast(TypeTemplateArgument) a) {
				import d.semantic.type;
				auto tv = TypeVisitor(pass);
				return TemplateArgument(tv.visit(ta.type));
			} else if(auto ia = cast(IdentifierTemplateArgument) a) {
				return iva.visit(ia.identifier);
			}
			
			assert(0, typeid(a).toString() ~ " is not supported.");
		}).array();
		
		// XXX: identifiableHandler shouldn't be necessary, we should pas a free function.
		auto instance = IdentifierVisitor!identifiableHandler(pass).visit(i.templateInstanciation.identifier).apply!((identified) {
			static if(is(typeof(identified) : Symbol)) {
				if(auto t = cast(Template) identified) {
					return TemplateInstancier(pass).instanciate(i.templateInstanciation.location, t, args, fargs);
				} else if(auto s = cast(OverloadSet) identified) {
					return TemplateInstancier(pass).instanciate(i.templateInstanciation.location, s, args, fargs);
				}
			}
			
			return cast(TemplateInstance) null;
		})();
		
		assert(instance);
		scheduler.require(instance, Step.Populated);
		
		// XXX: it should be possible to use handler here.
		// DMD doesn't like it.
		auto iv = IdentifierVisitor!identifiableHandler(pass);
		if(auto s = instance.dscope.resolve(i.name)) {
			return iv.visit(i.location, s).apply!handler();
		}
		
		// Let's try eponymous trick if the previous failed.
		auto name = i.templateInstanciation.identifier.name;
		if(i.name != name) {
			if(auto s = instance.dscope.resolve(name)) {
				return iv.resolveInSymbol(i.location, s, i.name).apply!handler();
			}
		}
		
		throw new CompileException(i.location, i.name.toString(context) ~ " not found in template");
	}
}

private:
enum Tag {
	Symbol,
	Expression,
	Type,
}

struct Identifiable {
	union {
		Symbol sym;
		Expression expr;
		Type type;
	}
	
	import d.ast.base : TypeQualifier;
	
	import std.bitmanip;
	mixin(bitfields!(
		Tag, "tag", 2,
		TypeQualifier, "qual", 3,
		uint, "", 3,
	));
	
	@disable this();
	
	// For type inference.
	this(typeof(null));
	
	this(Identifiable i) {
		this = i;
	}
	
	this(Symbol s) {
		tag = Tag.Symbol;
		sym = s;
	}
	
	this(Expression e) {
		tag = Tag.Expression;
		expr = e;
	}
	
	this(QualType qt) {
		tag = Tag.Type;
		qual = qt.qualifier;
		type = qt.type;
	}
	/+
	invariant() {
		final switch(tag) with(Tag) {
			case Type :
				assert(type);
				break;
			
			case Expression :
				assert(expr);
				break;
			
			case Symbol :
				if(cast(TypeSymbol) sym) {
					assert(0, "TypeSymbol must be resolved as Type.");
				} else if(cast(ValueSymbol) sym) {
					assert(0, "ExpressionSymbol must be resolved as Expression.");
				}
				
				assert(sym);
				break;
		}
	}
	+/
}

Identifiable identifiableHandler(T)(T t) {
	static if(is(T == typeof(null))) {
		assert(0);
	} else {
		return Identifiable(t);
	}
}

auto apply(alias handler)(Identifiable i) {
	final switch(i.tag) with(Tag) {
		case Symbol :
			return handler(i.sym);
		
		case Expression :
			return handler(i.expr);
		
		case Type :
			return handler(QualType(i.type, i.qual));
	}
}

/**
 * Resolve expression.identifier as type or expression.
 */
struct ExpressionDotIdentifierVisitor(alias handler) {
	private SemanticPass pass;
	alias pass this;
	
	alias Ret = typeof(handler(null));
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Ret visit(ExpressionDotIdentifier i) {
		import d.semantic.expression;
		auto ev = ExpressionVisitor(pass);
		return visit(i.location, i.name, ev.visit(i.expression));
	}
	
	Ret visit(Location location, Name name, Expression e) {
		if(auto s = SymbolInTypeResolver(pass).visit(name, e.type)) {
			return visit(location, e, s);
		}
		
		// XXX: probably bogus, should probably be done after delegating to type.
		if(auto pt = cast(PointerType) peelAlias(e.type).type) {
			e = new UnaryExpression(e.location, pt.pointed, UnaryOp.Dereference, e);
			return visit(location, name, e);
		}
		
		// Not found in expression, delegating to type.
		// XXX: Use apply here as we can't pass several contexts.
		return IdentifierVisitor!identifiableHandler(pass).resolveInType(location, e.type, name).apply!((identified) {
			static if(is(typeof(identified) : Expression)) {
				// expression.sizeof or similar stuffs.
				return handler(new BinaryExpression(location, identified.type, BinaryOp.Comma, e, identified));
			} else {
				return handler(pass.raiseCondition!Expression(location, "Can't resolve identifier " ~ name.toString(pass.context)));
			}
		})();
	}
	
	Ret visit(Location location, Expression e, Symbol s) {
		return this.dispatch!((s) {
			throw new CompileException(s.location, "Don't know how to dispatch that " ~ typeid(s).toString());
		})(location, e, s);
	}
	
	Ret visit(Location location, Expression e, OverloadSet s) {
		if(s.set.length == 1) {
			return visit(location, e, s.set[0]);
		}
		
		return handler(new PolysemousExpression(location, s.set.map!(delegate Expression(s) {
			if(auto f = cast(Function) s) {
				pass.scheduler.require(f, Step.Signed);
				return new MethodExpression(location, e, f);
			}
			
			assert(0, "not implemented: template with context");
		}).array()));
	}
	
	Ret visit(Location location, Expression e, Field f) {
		scheduler.require(f, Step.Signed);
		return handler(new FieldExpression(location, e, f));
	}
	
	Ret visit(Location location, Expression e, Function f) {
		scheduler.require(f, Step.Signed);
		return handler(new MethodExpression(location, e, f));
	}
	
	Ret visit(Location location, Expression e, Method m) {
		scheduler.require(m, Step.Signed);
		return handler(new MethodExpression(location, e, m));
	}
	
	Ret visit(Location location, Expression _, TypeAlias a) {
		// XXX: get rid of peelAlias and then get rid of this.
		scheduler.require(a);
		return handler(QualType(new AliasType(a)));
	}
	
	Ret visit(Location location, Expression _, Struct s) {
		return handler(QualType(new StructType(s)));
	}
	
	Ret visit(Location location, Expression _, Class c) {
		return handler(QualType(new ClassType(c)));
	}
	
	Ret visit(Location location, Expression _, Enum e) {
		return handler(QualType(new EnumType(e)));
	}
}

/**
 * Resolve symbols in types.
 */
struct SymbolInTypeResolver {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol visit(Name name, QualType t) {
		return this.dispatch!(t => null)(name, t.type);
	}
	
	Symbol visit(Name name, SliceType t) {
		if(name == BuiltinName!"length") {
			// FIXME: pass explicit location.
			auto location = Location.init;
			auto lt = getBuiltin(TypeKind.Ulong);
			auto s = new Field(location, 0, lt, BuiltinName!"length", null);
			s.step = Step.Processed;
			return s;
		} else if(name == BuiltinName!"ptr") {
			// FIXME: pass explicit location.
			auto location = Location.init;
			auto pt = QualType(new PointerType(t.sliced));
			auto s = new Field(location, 1, pt, BuiltinName!"ptr", null);
			s.step = Step.Processed;
			return s;
		}
		
		return null;
	}
	
	Symbol visit(Name name, AliasType t) {
		auto a = t.dalias;
		scheduler.require(a, Step.Populated);
		
		return visit(name, t.dalias.type);
	}
	
	Symbol visit(Name name, StructType t) {
		auto s = t.dstruct;
		scheduler.require(s, Step.Populated);
		
		return s.dscope.resolve(name);
	}
	
	Symbol visit(Name name, ClassType t) {
		auto c = t.dclass;
		scheduler.require(c, Step.Populated);
		
		auto s = c.dscope.resolve(name);
		if(s) {
			return s;
		}
		
		while(c !is c.base) {
			c = c.base;
			
			s = c.dscope.resolve(name);
			if(s) {
				return s;
			}
		}
		
		return null;
	}
	
	Symbol visit(Name name, EnumType t) {
		auto e = t.denum;
		scheduler.require(e, Step.Populated);
		
		auto s = e.dscope.resolve(name);
		return s ? s : visit(name, QualType(t.denum.type));
	}
}

