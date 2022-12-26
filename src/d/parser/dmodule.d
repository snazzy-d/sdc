module d.parser.dmodule;

import d.ast.declaration;

import d.parser.base;
import d.parser.declaration;

import source.name;

/**
 * Parse a whole module.
 * This is the regular entry point in the parser.
 */
auto parseModule(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Begin);

	Name name;
	Name[] packages;

	if (trange.front.type == TokenType.Module) {
		trange.popFront();
		name = trange.front.name;

		trange.match(TokenType.Identifier);
		while (trange.front.type == TokenType.Dot) {
			trange.popFront();

			packages ~= name;
			name = trange.front.name;

			trange.match(TokenType.Identifier);
		}

		trange.match(TokenType.Semicolon);
	}

	Declaration[] declarations;
	while (trange.front.type != TokenType.End) {
		declarations ~= trange.parseDeclaration();
	}

	return new Module(location.spanTo(trange.previous), name, packages,
	                  declarations);
}
