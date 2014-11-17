module d.parser.adt;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.ir.type;

import d.parser.base;
import d.parser.declaration;
import d.parser.dtemplate;
import d.parser.expression;
import d.parser.identifier;
import d.parser.type;

/**
 * Parse class
 */
auto parseClass(TokenRange)(ref TokenRange trange, StorageClass stc) if(isTokenRange!TokenRange) {
	return trange.parsePolymorphic!true(stc);
}

/**
 * Parse interface
 */
auto parseInterface(TokenRange)(ref TokenRange trange, StorageClass stc) if(isTokenRange!TokenRange) {
	return trange.parsePolymorphic!false(stc);
}

private Declaration parsePolymorphic(bool isClass = true, TokenRange)(ref TokenRange trange, StorageClass stc) {
	Location location = trange.front.location;
	
	static if(isClass) {
		trange.match(TokenType.Class);
		alias DeclarationType = ClassDeclaration;
	} else {
		trange.match(TokenType.Interface);
		alias DeclarationType = InterfaceDeclaration;
	}
	
	AstTemplateParameter[] parameters;
	if(trange.front.type == TokenType.OpenParen) {
		parameters = trange.parseTemplateParameters();
	}
	
	auto name = trange.front.name;
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
	
	auto adt = new DeclarationType(location, stc, name, bases, members);
	
	if(parameters.ptr) {
		return new TemplateDeclaration(location, stc, name, parameters, [adt]);
	} else {
		return adt;
	}
}

/**
 * Parse struct
 */
auto parseStruct(TokenRange)(ref TokenRange trange, StorageClass stc) if(isTokenRange!TokenRange) {
	return trange.parseMonomorphic!true(stc);
}

/**
 * Parse union
 */
auto parseUnion(TokenRange)(ref TokenRange trange, StorageClass stc) if(isTokenRange!TokenRange) {
	return trange.parseMonomorphic!false(stc);
}

private Declaration parseMonomorphic(bool isStruct = true, TokenRange)(ref TokenRange trange, StorageClass stc) {
	Location location = trange.front.location;
	
	static if(isStruct) {
		trange.match(TokenType.Struct);
		alias DeclarationType = StructDeclaration;
	} else {
		trange.match(TokenType.Union);
		alias DeclarationType = UnionDeclaration;
	}
		
	Name name;
	AstTemplateParameter[] parameters;
	
	if(trange.front.type == TokenType.Identifier) {
		name = trange.front.name;
		trange.popFront();
		
		switch(trange.front.type) {
			// Handle opaque declarations.
			case TokenType.Semicolon :
				location.spanTo(trange.front.location);
				
				trange.popFront();
				
				assert(0, "Opaque declaration aren't supported.");
			
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
	
	auto adt = new DeclarationType(location, stc, name, members);
	
	if(parameters.ptr) {
		return new TemplateDeclaration(location, stc, name, parameters, [adt]);
	} else {
		return adt;
	}
}

/**
 * Parse enums
 */
Declaration parseEnum(TokenRange)(ref TokenRange trange, StorageClass stc) in {
	assert(stc.isEnum == true);
} body {
	Location location = trange.front.location;
	trange.match(TokenType.Enum);
	
	Name name;
	QualAstType type;
	
	switch(trange.front.type) with(TokenType) {
		case Identifier :
			name = trange.front.name;
			trange.popFront();
			
			// Ensure we are not in case of manifest constant.
			assert(trange.front.type != Assign, "Manifest constant must be parsed as auto declaration and not as enums.");
			
			// If we have a colon, we go to the apropriate case.
			if(trange.front.type == Colon) {
				goto case Colon;
			}
			
			// If not, then it is time to parse the enum content.
			goto case OpenBrace;
		
		case Colon :
			trange.popFront();
			type = trange.parseType();
			
			break;
		
		case OpenBrace :
			// If no type is specified, uint is choosen by default.
			type = QualAstType(new BuiltinType(TypeKind.Uint));
			break;
		
		default :
			// TODO: error.
			trange.match(Begin);
	}
	
	assert(type.type, "type should have been set at this point.");
	
	trange.match(TokenType.OpenBrace);
	VariableDeclaration[] enumEntries;
	
	while(trange.front.type != TokenType.CloseBrace) {
		auto entryName = trange.front.name;
		auto entryLocation = trange.front.location;
		
		trange.match(TokenType.Identifier);
		
		AstExpression entryValue;
		if(trange.front.type == TokenType.Assign) {
			trange.popFront();
			
			entryValue = trange.parseAssignExpression();
			
			// FIXME: don't work for whatever reason.
			// entryLocation.spanTo(entryValue.location);
		}
		
		enumEntries ~= new VariableDeclaration(entryLocation, stc, type, entryName, entryValue);
		
		// If it is not a comma, then we abort the loop.
		if(trange.front.type != TokenType.Comma) break;
		
		trange.popFront();
	}
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.CloseBrace);
	
	return new EnumDeclaration(location, stc, name, type, enumEntries);
}

