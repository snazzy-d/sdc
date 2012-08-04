module d.ast.symbol;

import d.ast.base;
import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

class Symbol : Node {
	string name;
	string mangling;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
		
		// TODO: Generate proper mangling.
		this.mangling = name;
	}
}

/**
 * Any symbol that introduce its own scope.
 */
class ScopeSymbol : Symbol {
	private Scope s;
	
	this(Location location, string name) {
		super(location, name);
		
		this.s = new Scope();
	}
	
	this(Location location, string name, ScopeSymbol parent) {
		super(location, name);
		
		this.s = new NestedScope(parent.s);
		
		parent.s.addOverloadableSymbol(this);
	}
}

class ModuleSymbol : ScopeSymbol {
	ModuleDeclaration dmodule;
	Symbol[] symbols;
	
	this(ModuleDeclaration dmodule) {
		this(dmodule, []);
	}
	
	this(ModuleDeclaration dmodule, Symbol[] symbols) {
		super(dmodule.location, dmodule.name);
		
		this.dmodule = dmodule;
		this.symbols = symbols;
	}
}

class VariableSymbol : Symbol {
	Type type;
	Expression value;
	
	this(VariableDeclaration variable, ScopeSymbol parent) {
		this(variable.location, variable.type, variable.name, variable.value, parent);
	}
	
	this(Location location, Type type, string name, Expression value, ScopeSymbol parent) {
		super(location, name);
		
		this.type = type;
		this.value = value;
		
		parent.s.addSymbol(this);
	}
}

class FunctionSymbol : ScopeSymbol {
	Type returnType;
	Parameter[] parameters;
	Statement fbody;
	
	this(FunctionDefinition fun, ScopeSymbol parent) {
		super(fun.location, fun.name, parent);
		
		returnType = fun.returnType;
		parameters = fun.parameters;
		fbody = fun.fbody;
	}
}

/**
 * A scope associate identifier with declarations.
 */
class Scope {
	Symbol[string] symbols;
	
	void addSymbol(Symbol s) {
		symbols[s.name] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		// TODO: handle that properly.
		addSymbol(s);
	}
	
	Symbol resolve(string name) {
		return symbols[name];
	}
}

class NestedScope : Scope {
	Scope parent;
	
	this(Scope parent) {
		this.parent = parent;
	}
	
	override Symbol resolve(string name) {
		return symbols.get(name, parent.resolve(name));
	}
}

