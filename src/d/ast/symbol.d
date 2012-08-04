module d.ast.symbol;

import d.ast.base;
import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

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
}

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

class ModuleSymbol : Symbol {
	ModuleDeclaration dmodule;
	Symbol[] symbols;
	
	this(ModuleDeclaration dmodule, Symbol[] symbols) {
		super(dmodule.location, dmodule.name);
		
		this.dmodule = dmodule;
		this.symbols = symbols;
	}
}

class VariableSymbol : Symbol {
	Type type;
	Expression value;
	
	this(VariableDeclaration variable) {
		this(variable.location, variable.type, variable.name, variable.value);
	}
	
	this(Location location, Type type, string name, Expression value) {
		super(location, name);
		
		this.type = type;
		this.value = value;
		
		// s.addSymbol(this);
	}
}

class FunctionSymbol : Symbol {
	Type returnType;
	Parameter[] parameters;
	Statement fbody;
	
	this(FunctionDefinition fun) {
		super(fun.location, fun.name);
		
		returnType = fun.returnType;
		parameters = fun.parameters;
		fbody = fun.fbody;
		
		// s.addOverloadableSymbol(this);
	}
}

