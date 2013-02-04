module d.semantic.identifier;

import d.semantic.base;
import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.ambiguous;
import d.ast.expression;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.dmodule;
import d.ast.dtemplate;
import d.ast.dscope;
import d.ast.identifier;
import d.ast.type;

import sdc.location;

import std.algorithm;
import std.array;

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
				m = cast(Module) scheduler.require(m, Step.Populated);
				assert(m);
				
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
				// No symbol have been found in the module, look for other modules.
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
		
		if(auto t = resolved.asType()) {
			return visit(new TypeDotIdentifier(i.location, i.name, t));
		} else if(auto e = resolved.asExpression()) {
			return visit(new ExpressionDotIdentifier(i.location, i.name, e));
		} else if(auto s = resolved.asSymbol()) {
			s = scheduler.require(s, Step.Populated);
			
			if(auto m = cast(Module) s) {
				return visit(i.location, m.dscope.resolve(i.name));
			}
		}
		
		assert(0, "can't resolve " ~ i.name ~ ".");
	}
	
	Identifiable visit(ExpressionDotIdentifier i) {
		i.expression = pass.visit(i.expression);
		
		return expressionDotIdentifierVisitor.visit(i);
	}
	
	Identifiable visit(TypeDotIdentifier i) {
		i.type = pass.visit(i.type);
		
		return typeDotIdentifierVisitor.visit(i);
	}
	
	Identifiable visit(AmbiguousDotIdentifier i) {
		if(auto type = pass.visit(i.qualifier.type)) {
			return visit(new TypeDotIdentifier(i.location, i.name, type));
		} else if(auto expression = pass.visit(i.qualifier.expression)) {
			return visit(new ExpressionDotIdentifier(i.location, i.name, expression));
		}
		
		assert(0, "Ambiguous can't be deambiguated.");
	}
	
	Identifiable visit(TemplateInstanciationDotIdentifier i) {
		return templateDotIdentifierVisitor.resolve(i);
	}
	
	Identifiable visit(Location location, Symbol s) {
		return this.dispatch(location, s);
	}
	
	private auto getSymbolExpression(Location location, ExpressionSymbol s) {
		return Identifiable(new SymbolExpression(location, cast(ExpressionSymbol) scheduler.require(s)));
	}
	
	Identifiable visit(Location location, VariableDeclaration d) {
		return getSymbolExpression(location, d);
	}
	
	Identifiable visit(Location location, FunctionDeclaration d) {
		return getSymbolExpression(location, d);
	}
	
	Identifiable visit(Location location, FunctionDefinition d) {
		return getSymbolExpression(location, d);
	}
	
	Identifiable visit(Location location, Parameter d) {
		return getSymbolExpression(location, d);
	}
	
	Identifiable visit(Location location, FieldDeclaration d) {
		return Identifiable(new FieldExpression(location, new ThisExpression(location), cast(FieldDeclaration) scheduler.require(d)));
	}
	
	Identifiable visit(Location location, OverLoadSet s) {
		if(s.set.length == 1) {
			return visit(location, s.set[0]);
		}
		
		auto results = s.set.map!(delegate Identifiable(Symbol s) {
			return visit(location, s);
		}).array();
		
		Expression[] expressions;
		foreach(result; results) {
			if(auto asExpression = result.asExpression()) {
				expressions ~= asExpression;
			} else {
				// TODO: handle templates.
				assert(0, typeid(result).toString() ~ " is not supported in overload set.");
			}
		}
		
		return Identifiable(new PolysemousExpression(location, expressions));
		
		assert(0);
	}
	
	private auto getSymbolType(Location location, TypeSymbol s) {
		return Identifiable(new SymbolType(location, cast(TypeSymbol) scheduler.require(s)));
	}
	
	Identifiable visit(Location location, StructDefinition d) {
		return getSymbolType(location, d);
	}
	
	Identifiable visit(Location location, EnumDeclaration d) {
		return getSymbolType(location, d);
	}
	
	Identifiable visit(Location location, AliasDeclaration d) {
		d = cast(AliasDeclaration) scheduler.require(d);
		
		return Identifiable(d.type);
	}
	
	Identifiable visit(Location location, Module m) {
		m = cast(Module) scheduler.require(m, Step.Populated);
		
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
		if(Symbol s = symbolInTypeResolver.visit(i.name, i.type)) {
			if(auto os = cast(OverLoadSet) s) {
				assert(os.set.length == 1);
				
				s = os.set[0];
			}
			
			if(auto ts = cast(TypeSymbol) s) {
				return Identifiable(new SymbolType(i.location, ts));
			} else if(auto es = cast(ExpressionSymbol) s) {
				return Identifiable(new SymbolExpression(i.location, es));
			} else {
				assert(0, "what the hell is that symbol ???");
			}
		}
		
		switch(i.name) {
			case "init" :
				return Identifiable(new CastExpression(i.location, i.type, new DefaultInitializer(i.type)));
			
			case "sizeof" :
				return Identifiable(new SizeofExpression(i.location, i.type));
			
			default :
				auto msg = i.name ~ " can't be resolved in type.";
				
				import sdc.terminal;
				outputCaretDiagnostics(i.location, msg);
				
				assert(0, msg);
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
		auto e = pass.visit(i.expression);
		
		if(auto s = symbolInTypeResolver.visit(i.name, e.type)) {
			return visit(i.location, e, s);
		} else if(auto asExpr = typeDotIdentifierVisitor.visit(new TypeDotIdentifier(i.location, i.name, e.type)).asExpression()) {
			// expression.sizeof or similar stuffs.
			return Identifiable(new CommaExpression(i.location, e, asExpr));
		}
		
		return Identifiable(compilationCondition!Expression(i.location, "Can't resolve identifier."));
	}
	
	Identifiable visit(Location location, Expression e, Symbol s) {
		return this.dispatch!((s) {
			auto msg = "Don't know how to dispatch that " ~ typeid(s).toString() ~ ".";
			
			import sdc.terminal;
			outputCaretDiagnostics(s.location, msg);
			
			assert(0, msg);
		})(location, e, s);
	}
	
	Identifiable visit(Location location, Expression e, OverLoadSet s) {
		if(s.set.length == 1) {
			return this.dispatch(location, e, s.set[0]);
		}
		
		assert(0);
		
		/*
		auto results = s.set.map!(s => this.dispatch(location, e, s)).array();
		
		Expression[] expressions;
		foreach(result; results) {
			if(auto asExpression = result.asExpression()) {
				expressions ~= asExpression;
			} else {
				// TODO: handle templates.
				return Identifiable(compilationCondition!Expression(location, typeid(result).toString() ~ " is not supported in overload set."));
			}
		}
		
		return Identifiable(new PolysemousExpression(location, expressions));
		*/
	}
	
	Identifiable visit(Location location, Expression e, FieldDeclaration d) {
		return Identifiable(new FieldExpression(location, e, d));
	}
	
	Identifiable visit(Location location, Expression e, FunctionDefinition d) {
		return Identifiable(new MethodExpression(location, e, d));
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
		
		assert(0, i.name ~ " not found in template.");
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
	
	Symbol visit(TemplateDeclaration s) {
		return s;
	}
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
	
	Symbol visit(string name, Type t) {
		return this.dispatch(name, t);
	}
	
	Symbol visit(string name, BooleanType t) {
		return null;
	}
	
	Symbol visit(string name, IntegerType t) {
		return null;
	}
	
	Symbol visit(string name, FloatType t) {
		return null;
	}
	
	Symbol visit(string name, CharacterType t) {
		return null;
	}
	
	Symbol visit(string name, SliceType t) {
		switch(name) {
			case "length" :
				auto lt = new IntegerType(t.location, Integer.Ulong);
				auto s = new FieldDeclaration(new VariableDeclaration(t.location, lt, "length", new DefaultInitializer(lt)), 0);
				return pass.visit(s);
			
			case "ptr" :
				auto pt = new PointerType(t.location, t.type);
				auto s = new FieldDeclaration(new VariableDeclaration(t.location, pt, "ptr", new DefaultInitializer(pt)), 1);
				return pass.visit(s);
			
			default :
				return null;
		}
	}
	
	// XXX: why is this needed and not for struct/classes ?
	Symbol visit(string name, EnumType t) {
		auto d = cast(EnumDeclaration) scheduler.require(t.declaration, Step.Populated);
		auto s = d.dscope.resolve(name);
		
		return s?s:visit(name, t.type);
	}
	
	Symbol visit(string name, SymbolType t) {
		return this.dispatch(name, t.symbol);
	}
	
	Symbol visit(string name, AliasDeclaration a) {
		return visit(name, a.type);
	}
	
	Symbol visit(string name, StructDefinition s) {
		s = cast(StructDefinition) scheduler.require(s, Step.Populated);
		return s.dscope.resolve(name);
	}
	
	Symbol visit(string name, EnumDeclaration d) {
		d = cast(EnumDeclaration) scheduler.require(d, Step.Populated);
		return d.dscope.resolve(name);
	}
}

