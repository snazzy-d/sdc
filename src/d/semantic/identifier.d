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
	
	private Symbol resolveBasicIdentifier(BasicIdentifier i) {
		auto symbol = currentScope.search(i.name);
		
		if(symbol) {
			return symbol;
		}
		
		foreach(mod; currentScope.imports) {
			auto symInMod = mod.dscope.resolve(i.name);
			
			if(symInMod) {
				if(symbol) {
					assert(0, "Ambiguous symbol " ~ i.name);
				}
				
				symbol = symInMod;
			}
		}
		
		// No symbol have been found in the module, look for other modules.
		assert(symbol, "Symbol " ~ i.name ~ " has not been found.");
		
		return symbol;
	}
	
	Identifiable visit(BasicIdentifier i) {
		return visit(i.location, resolveBasicIdentifier(i));
	}
	
	Identifiable visit(IdentifierDotIdentifier i) {
		auto resolved = visit(i.identifier);
		
		if(auto t = resolved.asType()) {
			return visit(new TypeDotIdentifier(i.location, i.name, t));
		} else if(auto e = resolved.asExpression()) {
			return visit(new ExpressionDotIdentifier(i.location, i.name, e));
		} else {
			auto s = resolved.asSymbol();
			if(auto m = cast(Module) s) {
				return visit(i.location, m.dscope.resolve(i.name));
			}
			
			assert(0, "can't resolve " ~ i.name ~ ".");
		}
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
				assert(0, i.name ~ " can't be resolved in type.");
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
		return this.dispatch(location, e, s);
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
		return visit(identifierVisitor.resolveBasicIdentifier(i));
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
	
	Symbol visit(string name, IntegerType t) {
		return null;
	}
	
	Symbol visit(string name, SliceType t) {
		switch(name) {
			case "length" :
				auto lt = new IntegerType(t.location, Integer.Ulong);
				auto s = new FieldDeclaration(new VariableDeclaration(t.location, lt, "length", new DefaultInitializer(lt)), 0);
				return scheduler.register(s, pass.visit(s), Step.Processed);
			
			case "ptr" :
				auto pt = new PointerType(t.location, t.type);
				auto s = new FieldDeclaration(new VariableDeclaration(t.location, pt, "ptr", new DefaultInitializer(pt)), 1);
				return scheduler.register(s, pass.visit(s), Step.Processed);
			
			default :
				return null;
		}
	}
	
	Symbol visit(string name, EnumType t) {
		auto s = t.declaration.dscope.resolve(name);
		
		return s?s:visit(name, t.type);
	}
	
	Symbol visit(string name, SymbolType t) {
		return this.dispatch(name, t.symbol);
	}
	
	Symbol visit(string name, AliasDeclaration a) {
		return visit(name, a.type);
	}
	
	Symbol visit(string name, StructDefinition s) {
		return s.dscope.resolve(name);
	}
	
	Symbol visit(string name, EnumDeclaration d) {
		return d.dscope.resolve(name);
	}
}

