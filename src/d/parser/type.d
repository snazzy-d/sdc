module d.parser.type;

import d.ast.ambiguous;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.dfunction;
import d.parser.expression;
import d.parser.identifier;
import d.parser.util;

Type parseType(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto base = trange.parseBasicType();
	return trange.parseTypeSuffix!true(base);
}

Type parseConfirmedType(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto base = trange.parseBasicType();
	return trange.parseTypeSuffix!false(base);
}

auto parseBasicType(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	auto processQualifier(alias qualifyType)() {
		trange.popFront();
		
		if(trange.front.type == TokenType.OpenParen) {
			trange.popFront();
			auto type = trange.parseType();
			trange.match(TokenType.CloseParen);
			
			return qualifyType(type);
		}
		
		return qualifyType(trange.parseType());
	}
	
	switch(trange.front.type) {
		// Types qualifiers
		case TokenType.Const :
			return processQualifier!(function(Type type) { return type.makeConst(); })();
		
		case TokenType.Immutable :
			return processQualifier!(function(Type type) { return type.makeImmutable(); })();
		
		case TokenType.Mutable :
			return processQualifier!(function(Type type) { return type.makeMutable(); })();
		
		case TokenType.Inout :
			return processQualifier!(function(Type type) { return type.makeInout(); })();
		
		case TokenType.Shared, TokenType.Scope, TokenType.Ref :
			// TODO: handle shared, scope and ref.
			return processQualifier!(function(Type type) { return type; })();
		
		// Identified types
		case TokenType.Identifier :
			auto identifier = trange.parseIdentifier();
			location.spanTo(identifier.location);
			
			return new IdentifierType(location, identifier);
		
		case TokenType.Dot :
			auto identifier = trange.parseDotIdentifier();
			location.spanTo(identifier.location);
			
			return new IdentifierType(location, identifier);
		
		case TokenType.Typeof :
			return trange.parseTypeof();
		
		case TokenType.This :
			trange.popFront();
			auto thisExpression = new ThisExpression(location);
			trange.match(TokenType.Dot);
			auto identifier = trange.parseQualifiedIdentifier(location, thisExpression);
			location.spanTo(identifier.location);
			
			return new IdentifierType(location, identifier);
		
		case TokenType.Super :
			trange.popFront();
			auto superExpression = new SuperExpression(location);
			trange.match(TokenType.Dot);
			auto identifier = trange.parseQualifiedIdentifier(location, superExpression);
			location.spanTo(identifier.location);
			
			return new IdentifierType(location, identifier);
		
		// Basic types
		case TokenType.Bool :
			trange.popFront();
			return new BuiltinType!bool(location);
		
		case TokenType.Byte :
			trange.popFront();
			return new BuiltinType!byte(location);
		
		case TokenType.Ubyte :
			trange.popFront();
			return new BuiltinType!ubyte(location);
		
		case TokenType.Short :
			trange.popFront();
			return new BuiltinType!short(location);
		
		case TokenType.Ushort :
			trange.popFront();
			return new BuiltinType!ushort(location);
		
		case TokenType.Int :
			trange.popFront();
			return new BuiltinType!int(location);
		
		case TokenType.Uint :
			trange.popFront();
			return new BuiltinType!uint(location);
		
		case TokenType.Long :
			trange.popFront();
			return new BuiltinType!long(location);
		
		case TokenType.Ulong :
			trange.popFront();
			return new BuiltinType!ulong(location);
		
/*		case TokenType.Cent :
			trange.popFront();
			return new BuiltinType!cent(location);
		case TokenType.Ucent :
			trange.popFront();
			return new BuiltinType!ucent(location);	*/
		
		case TokenType.Char :
			trange.popFront();
			return new BuiltinType!char(location);
		
		case TokenType.Wchar :
			trange.popFront();
			return new BuiltinType!wchar(location);
		
		case TokenType.Dchar :
			trange.popFront();
			return new BuiltinType!dchar(location);
		
		case TokenType.Float :
			trange.popFront();
			return new BuiltinType!float(location);
		
		case TokenType.Double :
			trange.popFront();
			return new BuiltinType!double(location);
		
		case TokenType.Real :
			trange.popFront();
			return new BuiltinType!real(location);
		
		case TokenType.Void :
			trange.popFront();
			return new BuiltinType!void(location);
		
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
	BasicType type;
	
	Location location = trange.front.location;
	trange.match(TokenType.Typeof);
	trange.match(TokenType.OpenParen);
	
	if(trange.front.type == TokenType.Return) {
		trange.popFront();
		location.spanTo(trange.front.location);
		
		type = new ReturnType(location);
	} else {
		auto e = trange.parseExpression();
		location.spanTo(trange.front.location);
		
		type = new TypeofType(location, e);
	}
	
	trange.match(TokenType.CloseParen);
	
	return type;
}

/**
 * Parse *, [ ... ] and function/delegate types.
 */
private auto parseTypeSuffix(bool isGreedy, TokenRange)(ref TokenRange trange, Type type) {
	Location location = type.location;
	
	while(1) {
		switch(trange.front.type) {
			case TokenType.Asterix :
				location.spanTo(trange.front.location);
				trange.popFront();
				
				type = new PointerType(location, type);
				break;
				
			case TokenType.OpenBracket :
				type = trange.parseBracket(type);
				break;
			
			case TokenType.Dot :
				auto lookahead = trange.save;
				lookahead.popFront();
				if(lookahead.front.type != TokenType.Identifier) return type;
				
				static if(!isGreedy) {
					import d.parser.util;
					if(!trange.getConfirmedType()) {
						return type;
					}
				}
				
				trange.popFront();
				auto identifier = trange.parseQualifiedIdentifier(type.location, type);
				location.spanTo(identifier.location);
				
				type = new IdentifierType(location, identifier);
				break;
			
			case TokenType.Function :
				trange.popFront();
				bool isVariadic;
				auto parameters = trange.parseParameters(isVariadic);
				
				// TODO: fix location.
				location.spanTo(trange.front.location);
				
				// TODO: parse postfix attributes.
				return new FunctionType(location, type, parameters, isVariadic);
			
			case TokenType.Delegate :
				trange.popFront();
				bool isVariadic;
				auto parameters = trange.parseParameters(isVariadic);
				
				// TODO: fix location.
				location.spanTo(trange.front.location);
				
				// TODO: parse postfix attributes and storage class.
				return new DelegateType(location, type, parameters, isVariadic);
			
			default :
				return type;
		}
	}
}

private Type parseBracket(TokenRange)(ref TokenRange trange, Type type) {
	Location location = type.location;
	
	// -1 because we the match the opening [
	auto matchingBracket = trange.save;
	matchingBracket.popMatchingDelimiter!(TokenType.OpenBracket, TokenRange)();
	
	trange.match(TokenType.OpenBracket);
	if((matchingBracket - trange) == 1) {
		location.spanTo(trange.front.location);
		trange.popFront();
		
		return new SliceType(location, type);
	}
	
	return trange.parseTypeOrExpression!(delegate Type(parsed){
		location.spanTo(trange.front.location);
		trange.match(TokenType.CloseBracket);
		
		alias typeof(parsed) caseType;
		
		import d.ast.type;
		static if(is(caseType : Type)) {
			return new AssociativeArrayType(location, type, parsed);
		} else static if(is(caseType : Expression)) {
			return new StaticArrayType(location, type, parsed);
		} else {
			return new AmbiguousArrayType(location, type, parsed);
		}
	})(matchingBracket - trange - 1);
}

