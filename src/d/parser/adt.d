module d.parser.adt;

import d.ast.adt;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.declaration;
import d.parser.expression;
import d.parser.identifier;
import d.parser.type;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Parse class or interface
 */
auto parsePolymorphic(bool isClass = true)(TokenStream tstream) {
	static if(isClass) {
		auto location = match(tstream, TokenType.Class).location;
	} else {
		auto location = match(tstream, TokenType.Interface).location;
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
	
	static if(isClass) {
		return new ClassDefinition(location, name, bases, members);
	} else {
		return new InterfaceDefinition(location, name, bases, members);
	}
}

alias parsePolymorphic!true parseClass;
alias parsePolymorphic!false parseInterface;

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

/**
 * Parse enums
 */
Enum parseEnum(TokenStream tstream) {
	auto location = match(tstream, TokenType.Enum).location;
	string name;
	Type type;
	
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			name = tstream.get().value;
			
			// Ensure we are not in case of manifest constant.
			assert(tstream.peek.type != TokenType.Assign, "Manifest constant must be parsed as auto declaration and not as enums.");
			
			// If we have a colon, we go to the apropriate case.
			if(tstream.peek.type == TokenType.Colon) {
				goto case TokenType.Colon;
			}
			
			// If not, then it is time to parse the enum content.
			goto case TokenType.OpenBrace;
		
		case TokenType.Colon :
			tstream.get();
			type = parseType(tstream);
			
			break;
		
		case TokenType.OpenBrace :
			// If no type is specified, uint is choosen by default.
			type = new BuiltinType!uint(location);
			break;
		
		default :
			// TODO: error.
			assert(0);
	}
	
	match(tstream, TokenType.OpenBrace);
	Expression[string] enumEntriesValues;
	
	string previousName;
	while(tstream.peek.type != TokenType.CloseBrace) {
		string entryName = match(tstream, TokenType.Identifier).value;
		
		if(tstream.peek.type == TokenType.Assign) {
			tstream.get();
			
			enumEntriesValues[entryName] = parseAssignExpression(tstream);
		} else {
			auto entryLocation = tstream.previous.location;
			
			if(previousName.length > 0) {
				enumEntriesValues[entryName] = new AdditionExpression(entryLocation, enumEntriesValues[previousName], new IntegerLiteral!uint(entryLocation, 1));
			} else {
				enumEntriesValues[entryName] = new IntegerLiteral!uint(entryLocation, 0);
			}
		}
		
		// If it is not a comma, then we abort the loop.
		if(tstream.peek.type != TokenType.Comma) break;
		
		tstream.get();
		previousName = entryName;
	}
	
	location.spanTo(match(tstream, TokenType.CloseBrace).location);
	
	auto enumEntries = new VariablesDeclaration(location, type, enumEntriesValues);
	
	if(name.length == 0) {
		return new Enum(location, type, enumEntries);
	} else {
		return new NamedEnum(location, name, type, enumEntries);
	}
}

