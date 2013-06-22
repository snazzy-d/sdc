module d.parser.type;

import d.ast.base;
import d.ast.expression;
import d.ast.type;

import d.ir.expression;
import d.ir.type;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.dfunction;
import d.parser.expression;
import d.parser.identifier;
import d.parser.util;

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
	
	switch(trange.front.type) {
		// Types qualifiers
		case TokenType.Const :
			return processQualifier!(TypeQualifier.Const)();
		
		case TokenType.Immutable :
			return processQualifier!(TypeQualifier.Immutable)();
		
		case TokenType.Inout :
			return processQualifier!(TypeQualifier.Mutable)();
		
		case TokenType.Shared :
			return processQualifier!(TypeQualifier.Shared)();
		
		// Identified types
		case TokenType.Identifier :
			return QualAstType(new IdentifierType(trange.parseIdentifier()));
		
		case TokenType.Dot :
			return QualAstType(new IdentifierType(trange.parseDotIdentifier()));
		
		case TokenType.Typeof :
			return trange.parseTypeof();
		
		case TokenType.This :
			Location location = trange.front.location;
			auto thisExpression = new ThisExpression(location);
			
			trange.popFront();
			trange.match(TokenType.Dot);
			
			return QualAstType(new IdentifierType(trange.parseQualifiedIdentifier(location, thisExpression)));
		
		case TokenType.Super :
			Location location = trange.front.location;
			auto superExpression = new SuperExpression(location);
			
			trange.popFront();
			trange.match(TokenType.Dot);
			
			return QualAstType(new IdentifierType(trange.parseQualifiedIdentifier(location, superExpression)));
		
		// Basic types
		case TokenType.Void :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Void));
		
		case TokenType.Bool :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Bool));
		
		case TokenType.Char :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Char));
		
		case TokenType.Wchar :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Wchar));
		
		case TokenType.Dchar :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Dchar));
		
		case TokenType.Ubyte :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Ubyte));
		
		case TokenType.Ushort :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Ushort));
		
		case TokenType.Uint :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Uint));
		
		case TokenType.Ulong :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Ulong));
		
		case TokenType.Ucent :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Ucent));
		
		case TokenType.Byte :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Byte));
		
		case TokenType.Short :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Short));
		
		case TokenType.Int :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Int));
		
		case TokenType.Long :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Long));
		
		case TokenType.Cent :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Cent));
		
		case TokenType.Float :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Float));
		
		case TokenType.Double :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Double));
		
		case TokenType.Real :
			trange.popFront();
			return QualAstType(new BuiltinType(TypeKind.Real));
		
		default :
			trange.match(TokenType.Begin);
			// TODO: handle.
			// Erreur, basic type expected.
			assert(0);
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
		switch(trange.front.type) {
			case TokenType.Star :
				trange.popFront();
				
				type = QualAstType(new AstPointerType(type));
				break;
			
			case TokenType.OpenBracket :
				type = trange.parseBracket(type);
				break;
			
			case TokenType.Function :
				trange.popFront();
				bool isVariadic;
				auto parameters = trange.parseParameters(isVariadic);
				
				// TODO: parse postfix attributes.
				type = QualAstType(new AstFunctionType(Linkage.D, ParamAstType(type), parameters, isVariadic));
				break;
			
			case TokenType.Delegate :
				trange.popFront();
				bool isVariadic;
				auto parameters = trange.parseParameters(isVariadic);
				
				// TODO: parse postfix attributes and storage class.
				type = QualAstType(new AstDelegateType(Linkage.D, ParamAstType(type), ParamAstType.init, parameters, isVariadic));
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
			return QualAstType(new d.ast.type.ArrayType(type, parsed));
		} else {
			return QualAstType(new IdentifierArrayType(type, parsed));
		}
	})();
}

