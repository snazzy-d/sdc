module d.parser.dmodule;

import d.ast.declaration;
import d.ast.dmodule;

import d.parser.base;
import d.parser.declaration;

/**
 * Parse a whole module.
 * This is the regular entry point in the parser
 */
auto parseModule(TokenRange)(ref TokenRange trange, string name, string[] packages) if(isTokenRange!TokenRange) {
	trange.match(TokenType.Begin);
	Location location = trange.front.location;
	
	if(trange.front.type == TokenType.Module) {
		trange.popFront();
		string current = trange.front.value;
		string[] parsedPackages;
		
		trange.match(TokenType.Identifier);
		while(trange.front.type == TokenType.Dot) {
			trange.popFront();
			
			parsedPackages ~= current;
			current = trange.front.value;
			
			trange.match(TokenType.Identifier);
		}
		
		trange.match(TokenType.Semicolon);
		
		assert(current == name);
		assert(parsedPackages == packages);
	}
	
	Declaration[] declarations;
	while(trange.front.type != TokenType.End) {
		declarations ~= trange.parseDeclaration();
	}
	
	location.spanTo(trange.front.location);
	
	return new Module(location, name, packages, declarations);
}

