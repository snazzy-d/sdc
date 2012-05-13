module d.parser.adt;

import d.ast.adt;
import d.ast.declaration;
import d.ast.identifier;

import d.parser.declaration;
import d.parser.identifier;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Parse class
 */
auto parseClass(bool isInterface = false)(TokenStream tstream) {
	static if(isInterface) {
		auto location = match(tstream, TokenType.Interface).location;
	} else {
		auto location = match(tstream, TokenType.Class).location;
	}
	
	string name = match(tstream, TokenType.Identifier).value;
	Identifier[] bases;
	
	if(tstream.peek.type == TokenType.Colon) {
		do {
			tstream.get();
			bases ~= parseIdentifier(tstream);
		} while(tstream.peek.type == TokenType.Comma);
	}
	
	auto members = parseAggregate(tstream);
	
	location.spanTo(tstream.previous.location);
	
	static if(isInterface) {
		return new InterfaceDefinition(location, name, bases, members);
	} else {
		return new ClassDefinition(location, name, bases, members);
	}
}

/**
 * Parse struct
 */
auto parseStruct(TokenStream tstream) {
	auto location = match(tstream, TokenType.Struct).location;
	string name = match(tstream, TokenType.Identifier).value;
	
	// Handle opaque structs.
	if(tstream.peek.type == TokenType.Semicolon) {
		location.spanTo(tstream.peek.location);
		
		tstream.get();
		
		return new StructDeclaration(location, name);
	} else {
		auto members = parseAggregate(tstream);
		
		location.spanTo(tstream.previous.location);
		
		return new StructDefinition(location, name, members);
	}
}

