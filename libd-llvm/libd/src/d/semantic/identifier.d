module d.semantic.identifier;

import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.dfunction;
import d.ast.dmodule;
import d.ast.dtemplate;
import d.ast.identifier;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.exception;
import d.location;

import std.algorithm;
import std.array;

alias Module = d.ir.symbol.Module;

final class IdentifierVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private TypeDotIdentifierVisitor typeDotIdentifierVisitor;
	private ExpressionDotIdentifierVisitor expressionDotIdentifierVisitor;
	private SymbolInTypeResolver symbolInTypeResolver;
	private TemplateDotIdentifierVisitor templateDotIdentifierVisitor;
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		typeDotIdentifierVisitor		= new TypeDotIdentifierVisitor(this);
		expressionDotIdentifierVisitor	= new ExpressionDotIdentifierVisitor(this);
		symbolInTypeResolver			= new SymbolInTypeResolver(this);
		templateDotIdentifierVisitor	= new TemplateDotIdentifierVisitor(this);
	}
	
	Identifiable visit(Identifier i) {
		return this.dispatch(i);
	}
	
	private Symbol resolveImportedSymbol(string name) {
		auto dscope = currentScope;
		
		while(true) {
			Symbol symbol;
			
			foreach(m; dscope.imports) {
				scheduler.require(m, Step.Populated);
				
				auto symInMod = m.dscope.resolve(name);
				if(symInMod) {
					if(symbol) {
						assert(0, "Ambiguous symbol " ~ name);
					}
					
					symbol = symInMod;
				}
			}
			
			if(symbol) return symbol;
			
			if(auto nested = cast(NestedScope) dscope) {
				dscope = nested.parent;
			} else {
				assert(0, "Symbol " ~ name ~ " has not been found.");
			}
			
			if(auto nested = cast(SymbolScope) dscope) {
				scheduler.require(nested.symbol, Step.Populated);
			}
		}
	}
	
	private Symbol resolveName(string name) {
		auto symbol = currentScope.search(name);
		
		// I wish we had ?:
		return symbol ? symbol : resolveImportedSymbol(name);
	}
	
	Identifiable visit(BasicIdentifier i) {
		return visit(i.location, resolveName(i.name));
	}
	
	Identifiable visit(IdentifierDotIdentifier i) {
		auto resolved = visit(i.identifier);
		
		return resolved.apply!(delegate Identifiable(identified) {
			static if(is(typeof(identified) : QualType)) {
				return typeDotIdentifierVisitor.visit(i.location, i.name, identified);
			} else static if(is(typeof(identified) : Expression)) {
				return expressionDotIdentifierVisitor.visit(i.location, i.name, identified);
			} else {
				pass.scheduler.require(identified, pass.Step.Populated);
				
				if(auto m = cast(Module) identified) {
					return visit(i.location, m.dscope.resolve(i.name));
				}
				
				throw new CompileException(i.location, "Can't resolve " ~ i.name);
			}
		})();
	}
	
	Identifiable visit(ExpressionDotIdentifier i) {
		return expressionDotIdentifierVisitor.visit(i);
	}
	
	Identifiable visit(TypeDotIdentifier i) {
		return typeDotIdentifierVisitor.visit(i);
	}
	
	Identifiable visit(TemplateInstanciationDotIdentifier i) {
		return templateDotIdentifierVisitor.resolve(i);
	}
	
	Identifiable visit(IdentifierBracketIdentifier i) {
		assert(0, "Not implemented");
	}
	
	Identifiable visit(IdentifierBracketExpression i) {
		return visit(i.indexed).apply!(delegate Identifiable(identified) {
			static if(is(typeof(identified) : QualType)) {
				assert(0, "This is a type. I don't like that.");
				// return Identifiable(QualType(new StaticArrayType(identified, i.index)));
			} else static if(is(typeof(identified) : Expression)) {
				assert(0, "This is an expression. I don't like that.");
				// return Identifiable(new AstIndexExpression(i.location, identified, [i.index]));
			} else {
				assert(0, "WTF ???");
			}
		})();
	}
	
	Identifiable visit(Location location, Symbol s) {
		return this.dispatch(location, s);
	}
	
	Identifiable visit(Location location, TypeSymbol s) {
		return this.dispatch(location, s);
	}
	
	private auto getSymbolExpression(Location location, ValueSymbol s) {
		scheduler.require(s, Step.Signed);
		return Identifiable(new SymbolExpression(location, s));
	}
	
	Identifiable visit(Location location, Function f) {
		return getSymbolExpression(location, f);
	}
	
	Identifiable visit(Location location, Parameter p) {
		return getSymbolExpression(location, p);
	}
	
	Identifiable visit(Location location, Variable v) {
		return getSymbolExpression(location, v);
	}
	
	Identifiable visit(Location location, Field f) {
		scheduler.require(f, Step.Signed);
		return Identifiable(new FieldExpression(location, new ThisExpression(location), f));
	}
	
	Identifiable visit(Location location, OverLoadSet s) {
		if(s.set.length == 1) {
			return visit(location, s.set[0]);
		}
		
		Expression[] expressions;
		foreach(result; s.set.map!(s => visit(location, s))) {
			result.apply!((identified) {
				static if(is(typeof(identified) : Expression)) {
					expressions ~= identified;
				} else static if(is(typeof(identified) : QualType)) {
					assert(0, "Type can't be overloaded.");
				} else {
					// TODO: handle templates.
					throw new CompileException(identified.location, typeid(identified).toString() ~ " is not supported in overload set");
				}
			})();
		}
		
		return Identifiable(new PolysemousExpression(location, expressions));
	}
	
	Identifiable visit(Location location, TypeAlias a) {
		scheduler.require(a);
		return Identifiable(new AliasType(a));
	}
	
	Identifiable visit(Location location, Struct s) {
		return Identifiable(new StructType(s));
	}
	
	Identifiable visit(Location location, Class c) {
		return Identifiable(new ClassType(c));
	}
	
	Identifiable visit(Location location, Enum e) {
		return Identifiable(new EnumType(e));
	}
	
	Identifiable visit(Location location, Module m) {
		return Identifiable(m);
	}
}

/**
 * Resolve type.identifier as type or expression.
 */
final class TypeDotIdentifierVisitor {
	private IdentifierVisitor identifierVisitor;
	alias identifierVisitor this;
	
	this(IdentifierVisitor identifierVisitor) {
		this.identifierVisitor = identifierVisitor;
	}
	
	Identifiable visit(TypeDotIdentifier i) {
		return visit(i.location, i.name, pass.visit(i.type));
	}
	
	Identifiable visit(Location location, string name, QualType t) {
		if(Symbol s = symbolInTypeResolver.visit(name, t)) {
			if(auto os = cast(OverLoadSet) s) {
				assert(os.set.length == 1);
				
				s = os.set[0];
			}
			
			if(auto ts = cast(TypeSymbol) s) {
				return identifierVisitor.visit(location, ts);
			} else if(auto vs = cast(ValueSymbol) s) {
				scheduler.require(s, Step.Signed);
				return Identifiable(new SymbolExpression(location, vs));
			} else {
				throw new CompileException(s.location, "What the hell is that symbol ???");
			}
		}
		
		switch(name) {
			case "init" :
				assert(0, "init, yeah sure . . .");
			
			case "sizeof" :
				return Identifiable(new IntegerLiteral!false(location, sizeofCalculator.visit(t), TypeKind.Uint));
			
			default :
				throw new CompileException(location, name ~ " can't be resolved in type");
		}
	}
}

/**
 * Resolve expression.identifier as type or expression.
 */
final class ExpressionDotIdentifierVisitor {
	private IdentifierVisitor identifierVisitor;
	alias identifierVisitor this;
	
	this(IdentifierVisitor identifierVisitor) {
		this.identifierVisitor = identifierVisitor;
	}
	
	Identifiable visit(ExpressionDotIdentifier i) {
		return visit(i.location, i.name, pass.visit(i.expression));
	}
	
	Identifiable visit(Location location, string name, Expression e) {
		if(auto s = symbolInTypeResolver.visit(name, e.type)) {
			return visit(location, e, s);
		}
		
		// Not found in expression, delegating to type.
		return typeDotIdentifierVisitor.visit(location, name, e.type).apply!((identified) {
			static if(is(typeof(identified) : Expression)) {
				// expression.sizeof or similar stuffs.
				return Identifiable(new BinaryExpression(location, identified.type, BinaryOp.Comma, e, identified));
			} else {
				return Identifiable(identifierVisitor.pass.raiseCondition!Expression(location, "Can't resolve identifier " ~ name));
			}
		})();
	}
	
	Identifiable visit(Location location, Expression e, Symbol s) {
		return this.dispatch!((s) {
			throw new CompileException(s.location, "Don't know how to dispatch that " ~ typeid(s).toString());
		})(location, e, s);
	}
	
	Identifiable visit(Location location, Expression e, OverLoadSet s) {
		if(s.set.length == 1) {
			return this.dispatch(location, e, s.set[0]);
		}
		
		Expression[] expressions;
		foreach(result; s.set.map!(s => visit(location, e, s))) {
			result.apply!((identified) {
				static if(is(typeof(identified) : Expression)) {
					expressions ~= identified;
				} static if(is(typeof(identified) : QualType)) {
					assert(0, "Type can't be overloaded");
				} else {
					// TODO: handle templates.
					throw new CompileException(identified.location, typeid(identified).toString() ~ " is not supported in overload set");
				}
			})();
		}
		
		return Identifiable(new PolysemousExpression(location, expressions));
	}
	
	Identifiable visit(Location location, Expression e, Field f) {
		scheduler.require(f, Step.Signed);
		return Identifiable(new FieldExpression(location, e, f));
	}
	
	Identifiable visit(Location location, Expression e, Function f) {
		scheduler.require(f, Step.Signed);
		return Identifiable(new MethodExpression(location, e, f));
	}
	
	Identifiable visit(Location location, Expression e, Method m) {
		scheduler.require(m, Step.Signed);
		return Identifiable(new MethodExpression(location, e, m));
	}
	
	Identifiable visit(Location location, Expression _, TypeAlias a) {
		scheduler.require(a);
		return Identifiable(new AliasType(a));
	}
	
	Identifiable visit(Location location, Expression _, Struct s) {
		return Identifiable(new StructType(s));
	}
	
	Identifiable visit(Location location, Expression _, Class c) {
		return Identifiable(new ClassType(c));
	}
	
	Identifiable visit(Location location, Expression _, Enum e) {
		return Identifiable(new EnumType(e));
	}
}

/**
 * Resolve identifier!(arguments).identifier as type or expression.
 */
final class TemplateDotIdentifierVisitor {
	private IdentifierVisitor identifierVisitor;
	alias identifierVisitor this;
	
	this(IdentifierVisitor identifierVisitor) {
		this.identifierVisitor = identifierVisitor;
	}
	
	Identifiable resolve(TemplateInstanciationDotIdentifier i) {
		auto tplDecl = cast(TemplateDeclaration) this.dispatch(i.templateInstanciation.identifier);
		assert(tplDecl);
		/+
		auto instance = instanciate(i.templateInstanciation.location, tplDecl, i.templateInstanciation.arguments);
		if(auto s = instance.dscope.resolve(i.name)) {
			return identifierVisitor.visit(i.location, s);
		}
		
		// Let's try eponymous trick if the previous failed.
		if(i.name != tplDecl.name) {
			return identifierVisitor.visit(
				new IdentifierDotIdentifier(
					i.location,
					i.name,
					new TemplateInstanciationDotIdentifier(i.location, i.templateInstanciation.identifier.name, i.templateInstanciation)
				)
			);
		}
		+/
		throw new CompileException(i.location, i.name ~ " not found in template");
	}
	
	Symbol visit(BasicIdentifier i) {
		return visit(identifierVisitor.resolveName(i.name));
	}
	
	Symbol visit(Symbol s) {
		return this.dispatch(s);
	}
	
	Symbol visit(OverLoadSet s) {
		assert(s.set.length == 1);
		
		return visit(s.set[0]);
	}
	/+
	Symbol visit(TemplateDeclaration s) {
		return s;
	}
	+/
}

/**
 * Resolve symbols in types.
 */
final class SymbolInTypeResolver {
	private IdentifierVisitor identifierVisitor;
	alias identifierVisitor this;
	
	this(IdentifierVisitor identifierVisitor) {
		this.identifierVisitor = identifierVisitor;
	}
	
	Symbol visit(string name, QualType t) {
		return this.dispatch(name, t.type);
	}
	
	Symbol visit(string name, BuiltinType t) {
		return null;
	}
	
	Symbol visit(string name, SliceType t) {
		switch(name) {
			case "length" :
				// FIXME: pass explicit location.
				auto location = Location.init;
				auto lt = getBuiltin(TypeKind.Ulong);
				auto s = new Field(location, 0, lt, "length", null);
				s.step = Step.Processed;
				return s;
			
			case "ptr" :
				// FIXME: pass explicit location.
				auto location = Location.init;
				auto pt = QualType(new PointerType(t.sliced));
				auto s = new Field(location, 1, pt, "ptr", null);
				s.step = Step.Processed;
				return s;
			
			default :
				return null;
		}
	}
	
	Symbol visit(string name, AliasType t) {
		return visit(name, t.dalias.type);
	}
	
	Symbol visit(string name, StructType t) {
		auto s = t.dstruct;
		scheduler.require(s, Step.Populated);
		
		return s.dscope.resolve(name);
	}
	
	Symbol visit(string name, ClassType t) {
		auto c = t.dclass;
		scheduler.require(c, Step.Populated);
		
		return c.dscope.resolve(name);
	}
	
	Symbol visit(string name, EnumType t) {
		auto e = t.denum;
		scheduler.require(e, Step.Populated);
		
		auto s = e.dscope.resolve(name);
		return s?s:visit(name, QualType(t.denum.type));
	}
}

