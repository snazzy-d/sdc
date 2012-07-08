module d.parser.adt;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;
import d.parser.dtemplate;
import d.parser.expression;
import d.parser.identifier;
import d.parser.type;

import sdc.location;
import sdc.token;

/**
 * Parse class
 */
auto parseClass(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	return trange.parsePolymorphic!true();
}

/**
 * Parse interface
 */
auto parseInterface(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	return trange.parsePolymorphic!false();
}

private Declaration parsePolymorphic(bool isClass = true, TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	static if(isClass) {
		trange.match(TokenType.Class);
		alias ClassDefinition DefinitionType;
	} else {
		trange.match(TokenType.Interface);
		alias InterfaceDefinition DefinitionType;
	}
	
	TemplateParameter[] parameters;
	if(trange.front.type == TokenType.OpenParen) {
		parameters = trange.parseTemplateParameters();
	}
	
	string name = trange.front.value;
	trange.match(TokenType.Identifier);
	
	Identifier[] bases;
	if(trange.front.type == TokenType.Colon) {
		do {
			trange.popFront();
			bases ~= trange.parseIdentifier();
		} while(trange.front.type == TokenType.Comma);
	}
	
	if(parameters.ptr) {
		if(trange.front.type == TokenType.If) {
			trange.parseConstraint();
		}
	}
	
	auto members = trange.parseAggregate();
	
	location.spanTo(trange.front.location);
	
	auto adt = new DefinitionType(location, name, bases, members);
	
	if(parameters.ptr) {
		return new TemplateDeclaration(location, name, parameters, [adt]);
	} else {
		return adt;
	}
}

/**
 * Parse struct
 */
auto parseStruct(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	return trange.parseMonomorphic!true();
}

/**
 * Parse union
 */
auto parseUnion(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	return trange.parseMonomorphic!false();
}

private Declaration parseMonomorphic(bool isStruct = true, TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	static if(isStruct) {
		trange.match(TokenType.Struct);
		alias StructDeclaration DeclarationType;
		alias StructDefinition DefinitionType;
	} else {
		trange.match(TokenType.Union);
		alias UnionDeclaration DeclarationType;
		alias UnionDefinition DefinitionType;
	}
	
	string name;
	TemplateParameter[] parameters;
	
	if(trange.front.type == TokenType.Identifier) {
		name = trange.front.value;
		trange.popFront();
		
		switch(trange.front.type) {
			// Handle opaque declarations.
			case TokenType.Semicolon :
				location.spanTo(trange.front.location);
				
				trange.popFront();
				
				return new DeclarationType(location, name);
			
			// Template structs
			case TokenType.OpenParen :
				parameters = trange.parseTemplateParameters();
				
				if(trange.front.type == TokenType.If) {
					trange.parseConstraint();
				}
				
				break;
			
			default :
				break;
		}
	}
	
	auto members = trange.parseAggregate();
	
	location.spanTo(trange.front.location);
	
	auto adt = new DefinitionType(location, name, members);
	
	if(parameters.ptr) {
		return new TemplateDeclaration(location, name, parameters, [adt]);
	} else {
		return adt;
	}
}

/**
 * Parse enums
 */
Enum parseEnum(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Enum);
	
	string name;
	Type type;
	
	switch(trange.front.type) {
		case TokenType.Identifier :
			name = trange.front.value;
			trange.popFront();
			
			// Ensure we are not in case of manifest constant.
			assert(trange.front.type != TokenType.Assign, "Manifest constant must be parsed as auto declaration and not as enums.");
			
			// If we have a colon, we go to the apropriate case.
			if(trange.front.type == TokenType.Colon) {
				goto case TokenType.Colon;
			}
			
			// If not, then it is time to parse the enum content.
			goto case TokenType.OpenBrace;
		
		case TokenType.Colon :
			trange.popFront();
			type = trange.parseType();
			
			break;
		
		case TokenType.OpenBrace :
			// If no type is specified, uint is choosen by default.
			type = new BuiltinType!uint(location);
			break;
		
		default :
			// TODO: error.
			trange.match(TokenType.Begin);
	}
	
	trange.match(TokenType.OpenBrace);
	Expression[string] enumEntriesValues;
	
	string previousName;
	while(trange.front.type != TokenType.CloseBrace) {
		string entryName = trange.front.value;
		auto entryLocation = trange.front.location;
		
		trange.match(TokenType.Identifier);
		
		if(trange.front.type == TokenType.Assign) {
			trange.popFront();
			
			enumEntriesValues[entryName] = trange.parseAssignExpression();
		} else {
			if(previousName) {
				enumEntriesValues[entryName] = new AdditionExpression(entryLocation, enumEntriesValues[previousName], new IntegerLiteral!uint(entryLocation, 1));
			} else {
				enumEntriesValues[entryName] = new IntegerLiteral!uint(entryLocation, 0);
			}
		}
		
		// If it is not a comma, then we abort the loop.
		if(trange.front.type != TokenType.Comma) break;
		
		trange.popFront();
		previousName = entryName;
	}
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.CloseBrace);
	
	auto enumEntries = new VariablesDeclaration(location, []);
	
	if(name) {
		return new NamedEnum(location, name, type, enumEntries);
	} else {
		return new Enum(location, type, enumEntries);
	}
}

