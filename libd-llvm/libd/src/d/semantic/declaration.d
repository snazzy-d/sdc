module d.semantic.declaration;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.conditional;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;

import std.algorithm;
import std.array;
import std.range;

final class DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol[] flatten(Declaration[] decls, Symbol parent) {
		auto oldFlattenedDecls = flattenedDecls;
		scope(exit) flattenedDecls = oldFlattenedDecls;
		
		flattenedDecls = [];
		
		foreach(d; decls) {
			visit(d);
		}
		
		if(parent) {
			scheduler.register(parent, parent, Step.Populated);
		}
		
		return flattenedDecls;
	}
	
	void visit(Declaration d) {
		return this.dispatch(d);
	}
	
	private void select(Symbol s) {
		flattenedDecls ~= scheduler.schedule(s.repeat(1), s => pass.visit(s));
	}
	
	void visit(FunctionDeclaration d) {
		d.linkage = linkage;
		d.isStatic = isStatic;
		d.isEnum = true;
		
		currentScope.addOverloadableSymbol(d);
		
		if(d.fbody) {
			// XXX: move that to symbol pass.
			auto oldScope = currentScope;
			scope(exit) currentScope = oldScope;
			
			currentScope = d.dscope = new NestedScope(oldScope);
			
			foreach(p; d.parameters) {
				currentScope.addSymbol(p);
			}
		}
		
		select(d);
	}
	
	void visit(VariableDeclaration d) {
		if(buildFields && !isStatic) {
			d = new FieldDeclaration(d, fieldIndex++);
		}
		
		d.linkage = linkage;
		d.isStatic = isStatic;
		
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(VariablesDeclaration d) {
		foreach(var; d.variables) {
			visit(var);
		}
	}
	
	void visit(StructDefinition d) {
		d.linkage = linkage;
		
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(ClassDefinition d) {
		d.linkage = linkage;
		
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(EnumDeclaration d) {
		d.linkage = linkage;
		
		if(d.name) {
			currentScope.addSymbol(d);
			
			select(d);
		} else {
			auto type = (cast(EnumType) d.type).type;
			
			// XXX: Code duplication with symbols. Refactor.
			VariableDeclaration previous;
			foreach(e; d.enumEntries) {
				e.isEnum = true;
				
				if(typeid({ return e.value; }()) is typeid(DefaultInitializer)) {
					if(previous) {
						e.value = new AddExpression(e.location, new SymbolExpression(e.location, previous), makeLiteral(e.location, 1));
					} else {
						e.value = makeLiteral(e.location, 0);
					}
				}
				
				e.value = new CastExpression(e.location, type, e.value);
				e.type = type;
				
				previous = e;
				
				visit(e);
			}
		}
	}
	
	void visit(TemplateDeclaration d) {
		d.linkage = linkage;
		d.isStatic = isStatic;
		
		currentScope.addOverloadableSymbol(d);
		
		d.parentScope = currentScope;
		
		select(d);
	}
	
	void visit(AliasDeclaration d) {
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(LinkageDeclaration d) {
		auto oldLinkage = linkage;
		scope(exit) linkage = oldLinkage;
		
		linkage = d.linkage;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	void visit(StaticDeclaration d) {
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = true;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	void visit(ImportDeclaration d) {
		auto names = d.modules.map!(pkg => pkg.join(".")).array();
		auto filenames = d.modules.map!(pkg => pkg.join("/") ~ ".d").array();
		
		Module[] addToScope;
		foreach(name; d.modules) {
			addToScope ~= importModule(name);
		}
		
		currentScope.imports ~= addToScope;
	}
	
	void visit(StaticIfElse!Declaration d) {
		auto condition = evaluate(explicitCast(d.condition.location, new BooleanType(d.condition.location), pass.visit(d.condition)));
		
		if((cast(BooleanLiteral) condition).value) {
			foreach(item; d.items) {
				visit(item);
			}
		} else {
			foreach(item; d.elseItems) {
				visit(item);
			}
		}
	}
	
	void visit(Version!Declaration d) {
		foreach(v; versions) {
			if(d.versionId == v) {
				foreach(item; d.items) {
					visit(item);
				}
				
				return;
			}
		}
		
		// Version has not been found.
		foreach(item; d.elseItems) {
			visit(item);
		}
	}
	
	void visit(Mixin!Declaration d) {
		auto value = evaluate(pass.visit(d.value));
		
		// XXX: in order to avoid identifier resolution weirdness.
		auto location = d.location;
		
		if(auto str = cast(StringLiteral) value) {
			import d.lexer;
			auto source = new MixinSource(location, str.value);
			auto trange = lex!((line, begin, length) => Location(source, line, begin, length))(str.value ~ '\0');
			
			trange.match(TokenType.Begin);
			
			while(trange.front.type != TokenType.End) {
				visit(trange.parseDeclaration());
			}
		} else {
			assert(0, "mixin parameter should evalutate as a string.");
		}
	}
}

