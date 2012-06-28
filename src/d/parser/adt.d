module d.parser.adt;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.declaration;
import d.parser.dtemplate;
import d.parser.expression;
import d.parser.identifier;
import d.parser.type;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Parse class or interface
 */
Declaration parsePolymorphic(bool isClass = true)(TokenStream tstream) {
	static if(isClass) {
		auto location = match(tstream, TokenType.Class).location;
		alias ClassDefinition DefinitionType;
	} else {
		auto location = match(tstream, TokenType.Interface).location;
		alias InterfaceDefinition DefinitionType;
	}
	
	TemplateParameter[] parameters;
	if(tstream.peek.type == TokenType.OpenParen) {
		parameters = parseTemplateParameters(tstream);
	}
	
	string name = match(tstream, TokenType.Identifier).value;
	Identifier[] bases;
	
	if(tstream.peek.type == TokenType.Colon) {
		do {
			tstream.get();
			bases ~= parseIdentifier(tstream);
		} while(tstream.peek.type == TokenType.Comma);
	}
	
	if(parameters.ptr) {
		if(tstream.peek.type == TokenType.If) {
			parseConstraint(tstream);
		}
	}
	
	auto members = parseAggregate(tstream);
	
	location.spanTo(tstream.previous.location);
	
	auto adt = new DefinitionType(location, name, bases, members);
	
	if(parameters.ptr) {
		return new TemplateDeclaration(location, name, parameters, [adt]);
	} else {
		return adt;
	}
}

alias parsePolymorphic!true parseClass;
alias parsePolymorphic!false parseInterface;

/**
 * Parse struct or union
 */
Declaration parseStructOrUnion(TokenType type)(TokenStream tstream) if(type == TokenType.Struct || type == TokenType.Union) {
	auto location = match(tstream, type).location;
	
	string name;
	TemplateParameter[] parameters;
	
	if(tstream.peek.type == TokenType.Identifier) {
		name = tstream.get().value;
		
		switch(tstream.peek.type) {
			// Handle opaque declarations.
			case TokenType.Semicolon :
				location.spanTo(tstream.peek.location);
				
				tstream.get();
				
				return new StructDeclaration(location, name);
			
			// Template structs
			case TokenType.OpenParen :
				parameters = parseTemplateParameters(tstream);
				
				if(tstream.peek.type == TokenType.If) {
					parseConstraint(tstream);
				}
				
				break;
			
			default :
				break;
		}
	}
	
	auto members = parseAggregate(tstream);
	
	location.spanTo(tstream.previous.location);
	
	auto adt = new StructDefinition(location, name, members);
	
	if(parameters.ptr) {
		return new TemplateDeclaration(location, name, parameters, [adt]);
	} else {
		return adt;
	}
}

alias parseStructOrUnion!(TokenType.Struct) parseStruct;
alias parseStructOrUnion!(TokenType.Union) parseUnion;

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
			match(tstream, TokenType.Begin);
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
			
			if(previousName) {
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
	
	if(name) {
		return new NamedEnum(location, name, type, enumEntries);
	} else {
		return new Enum(location, type, enumEntries);
	}
}

