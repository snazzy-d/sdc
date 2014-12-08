module d.parser.type;

import d.ast.expression;
import d.ast.type;

import d.ir.expression;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.expression;
import d.parser.identifier;
import d.parser.util;

import std.algorithm;
import std.array;

QualAstType parseType(ParseMode mode = ParseMode.Greedy, TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto base = trange.parseBasicType();
	return trange.parseTypeSuffix!mode(base);
}

auto parseBasicType(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto processQualifier(TypeQualifier qualifier)() {
		trange.popFront();
		
		QualAstType type;
		if(trange.front.type == TokenType.OpenParen) {
			trange.popFront();
			type = trange.parseType();
			trange.match(TokenType.CloseParen);
		} else {
			type = trange.parseType();
		}
		
		return QualAstType(type.type, type.qualifier.add(qualifier));
	}
	
	switch(trange.front.type) with(TokenType) {
		// Types qualifiers
		case Const :
			return processQualifier!(TypeQualifier.Const)();
		
		case Immutable :
			return processQualifier!(TypeQualifier.Immutable)();
		
		case Inout :
			return processQualifier!(TypeQualifier.Mutable)();
		
		case Shared :
			return processQualifier!(TypeQualifier.Shared)();
		
		// Identified types
		case Identifier :
			return QualAstType(new IdentifierType(trange.parseIdentifier()));
		
		case Dot :
			return QualAstType(new IdentifierType(trange.parseDotIdentifier()));
		
		case Typeof :
			return trange.parseTypeof();
		
		case This :
			Location location = trange.front.location;
			auto thisExpression = new ThisExpression(location);
			
			trange.popFront();
			trange.match(Dot);
			
			return QualAstType(new IdentifierType(trange.parseQualifiedIdentifier(location, thisExpression)));
		
		case Super :
			Location location = trange.front.location;
			auto superExpression = new SuperExpression(location);
			
			trange.popFront();
			trange.match(TokenType.Dot);
			
			return QualAstType(new IdentifierType(trange.parseQualifiedIdentifier(location, superExpression)));
		
		// Basic types
		case Void :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Void));
		
		case Bool :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Bool));
		
		case Char :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Char));
		
		case Wchar :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Wchar));
		
		case Dchar :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Dchar));
		
		case Ubyte :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Ubyte));
		
		case Ushort :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Ushort));
		
		case Uint :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Uint));
		
		case Ulong :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Ulong));
		
		case Ucent :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Ucent));
		
		case Byte :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Byte));
		
		case Short :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Short));
		
		case Int :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Int));
		
		case Long :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Long));
		
		case Cent :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Cent));
		
		case Float :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Float));
		
		case Double :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Double));
		
		case Real :
			trange.popFront();
			return QualAstType(new BuiltinAstType(BuiltinType.Real));
		
		default :
			trange.match(Begin);
			// TODO: handle.
			// Erreur, basic type expected.
			assert(0,"Expected BasicType");
	}
}

/**
 * Parse typeof(...)
 */
private auto parseTypeof(TokenRange)(ref TokenRange trange) {
	AstType type;
	
	trange.match(TokenType.Typeof);
	trange.match(TokenType.OpenParen);
	
	if(trange.front.type == TokenType.Return) {
		trange.popFront();
		
		type = new ReturnType();
	} else {
		type = new TypeofType(trange.parseExpression());
	}
	
	trange.match(TokenType.CloseParen);
	
	return QualAstType(type);
}

/**
 * Parse *, [ ... ] and function/delegate types.
 */
QualAstType parseTypeSuffix(ParseMode mode, TokenRange)(ref TokenRange trange, QualAstType type) if(isTokenRange!TokenRange) {
	while(1) {
		switch(trange.front.type) with(TokenType) {
			case Star :
				trange.popFront();
				
				type = QualAstType(new AstPointerType(type));
				break;
			
			case OpenBracket :
				type = trange.parseBracket(type);
				break;
			
			case Function :
				trange.popFront();
				
				import d.parser.declaration;
				bool isVariadic;
				auto parameters = trange.parseParameters(isVariadic).map!(d => d.type).array();
				
				// TODO: parse postfix attributes.
				// TODO: ref return.
				type = QualAstType(new AstFunctionType(Linkage.D, ParamAstType(type, false), parameters, isVariadic));
				break;
			
			case Delegate :
				trange.popFront();
				
				import d.parser.declaration;
				bool isVariadic;
				auto parameters = trange.parseParameters(isVariadic).map!(d => d.type).array();
				
				// TODO: parse postfix attributes and storage class.
				// TODO: ref return.
				type = QualAstType(new AstDelegateType(Linkage.D, ParamAstType(type, false), ParamAstType.init, parameters, isVariadic));
				break;
			
			static if(mode == ParseMode.Greedy) {
				case TokenType.Dot :
					trange.popFront();
					
					// TODO: Duplicate function and pass location explicitely.
					type = QualAstType(new IdentifierType(trange.parseQualifiedIdentifier(trange.front.location, type)));
					break;
			}
			
			default :
				return type;
		}
	}
}

private QualAstType parseBracket(TokenRange)(ref TokenRange trange, QualAstType type) {
	trange.match(TokenType.OpenBracket);
	if(trange.front.type == TokenType.CloseBracket) {
		trange.popFront();
		
		return QualAstType(new AstSliceType(type));
	}
	
	return trange.parseAmbiguous!(delegate QualAstType(parsed) {
		trange.match(TokenType.CloseBracket);
		
		alias typeof(parsed) caseType;
		
		import d.ast.type;
		static if(is(caseType : QualAstType)) {
			return QualAstType(new AstAssociativeArrayType(type, parsed));
		} else static if(is(caseType : AstExpression)) {
			return QualAstType(new AstArrayType(type, parsed));
		} else {
			return QualAstType(new IdentifierArrayType(type, parsed));
		}
	})();
}

