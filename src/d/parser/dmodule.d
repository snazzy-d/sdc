module d.parser.dmodule;

import d.ast.declaration;
import d.ast.dmodule;

import d.parser.declaration;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

auto parseModule(TokenStream tstream) {
	auto location = match(tstream, TokenType.Begin).location;
	
	ModuleDeclaration moduleDeclaration;
	if(tstream.peek.type == TokenType.Module) {
		moduleDeclaration = parseModuleDeclaration(tstream);
	} else {
		// TODO: compute a correct declaration according to the filename.
		moduleDeclaration = new ModuleDeclaration(location, "", [""]);
	}
	
	Declaration[] declarations;
	while(tstream.peek.type != TokenType.End) {
		declarations ~= parseDeclaration(tstream);
	}
	
	location.spanTo(tstream.previous.location);
	tstream.get();
	
	return new Module(location, moduleDeclaration, declarations);
}

auto parseModuleDeclaration(TokenStream tstream) {
	auto location = match(tstream, TokenType.Module).location;
	
	string[] packages;
	string name = match(tstream, TokenType.Identifier).value;
	while(tstream.peek.type == TokenType.Dot) {
		tstream.get();
		packages ~= name;
		name = match(tstream, TokenType.Identifier).value;
	}
	
	location.spanTo(match(tstream, TokenType.Semicolon).location);
	
	return new ModuleDeclaration(location, name, packages);
}

