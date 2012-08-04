module d.ast.symbol;

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.identifier;

/**
 * A scope associate identifier with declarations.
 */
class Scope {
	Symbol[string] symbols;
	
	void addSymbol(Symbol s) {
		symbols[s.getName()] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		// TODO: handle that properly.
		addSymbol(s);
	}
}

class Symbol {
	abstract string getName();
}

class VariableSymbol : Symbol {
	VariableDeclaration variable;
	
	this(VariableDeclaration variable, Scope s) {
		this.variable = variable;
		
		s.addSymbol(this);
	}
	
	override string getName() {
		return variable.name;
	}
}

class FunctionSymbol : Symbol {
	FunctionDefinition fun;
	
	this(FunctionDefinition fun, Scope s) {
		this.fun = fun;
		
		s.addOverloadableSymbol(this);
	}
	
	override string getName() {
		return fun.name;
	}
}

