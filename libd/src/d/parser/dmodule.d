module d.parser.dmodule;

import d.ast.declaration;
import d.ast.dmodule;

import d.parser.base;
import d.parser.declaration;

import d.context.name;

/**
 * Parse a whole module.
 * This is the regular entry point in the parser
 */
auto parseModule(ref TokenRange trange, Name name, Name[] packages) {
	trange.match(TokenType.Begin);
	Location location = trange.front.location;
	
	if (trange.front.type == TokenType.Module) {
		trange.popFront();
		auto current = trange.front.name;
		Name[] parsedPackages;
		
		trange.match(TokenType.Identifier);
		while(trange.front.type == TokenType.Dot) {
			trange.popFront();
			
			parsedPackages ~= current;
			current = trange.front.name;
			
			trange.match(TokenType.Identifier);
		}
		
		trange.match(TokenType.Semicolon);
		
		assert(current == name);
		assert(parsedPackages == packages[$ - parsedPackages.length .. $]);
		
		packages = parsedPackages;
	}
	
	Declaration[] declarations;
	while(trange.front.type != TokenType.End) {
		declarations ~= trange.parseDeclaration();
	}
	
	location.spanTo(trange.front.location);
	
	return new Module(location, name, packages, declarations);
}
