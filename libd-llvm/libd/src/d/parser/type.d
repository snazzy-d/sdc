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
			return new IdentifierType(trange.parseIdentifier());
		
		case TokenType.Dot :
			return new IdentifierType(trange.parseDotIdentifier());
		
		case TokenType.Typeof :
			return trange.parseTypeof();
		
		case TokenType.This :
			auto thisExpression = new ThisExpression(location);
			
			trange.popFront();
			trange.match(TokenType.Dot);
			
			return new IdentifierType(trange.parseQualifiedIdentifier(location, thisExpression));
		
		case TokenType.Super :
			auto superExpression = new SuperExpression(location);
			
			trange.popFront();
			trange.match(TokenType.Dot);
			
			return new IdentifierType(trange.parseQualifiedIdentifier(location, superExpression));
		
		// Basic types
		case TokenType.Bool :
			trange.popFront();
			return new BooleanType(location);
		
		case TokenType.Byte :
			trange.popFront();
			return new IntegerType(location, IntegerOf!byte);
		
		case TokenType.Ubyte :
			trange.popFront();
			return new IntegerType(location, IntegerOf!ubyte);
		
		case TokenType.Short :
			trange.popFront();
			return new IntegerType(location, IntegerOf!short);
		
		case TokenType.Ushort :
			trange.popFront();
			return new IntegerType(location, IntegerOf!ushort);
		
		case TokenType.Int :
			trange.popFront();
			return new IntegerType(location, IntegerOf!int);
		
		case TokenType.Uint :
			trange.popFront();
			return new IntegerType(location, IntegerOf!uint);
		
		case TokenType.Long :
			trange.popFront();
			return new IntegerType(location, IntegerOf!long);
		
		case TokenType.Ulong :
			trange.popFront();
			return new IntegerType(location, IntegerOf!ulong);
		
/*		case TokenType.Cent :
			trange.popFront();
			return new BuiltinType!cent(location);
		
		case TokenType.Ucent :
			trange.popFront();
			return new BuiltinType!ucent(location);	*/
		
		case TokenType.Char :
			trange.popFront();
			return new CharacterType(location, CharacterOf!char);
		
		case TokenType.Wchar :
			trange.popFront();
			return new CharacterType(location, CharacterOf!wchar);
		
		case TokenType.Dchar :
			trange.popFront();
			return new CharacterType(location, CharacterOf!dchar);
		
		case TokenType.Float :
			trange.popFront();
			return new FloatType(location, Float.Float);
		
		case TokenType.Double :
			trange.popFront();
			return new FloatType(location, Float.Double);
		
		case TokenType.Real :
			trange.popFront();
			return new FloatType(location, Float.Real);
		
		case TokenType.Void :
			trange.popFront();
			return new VoidType(location);
		
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
				
				type = new IdentifierType(trange.parseQualifiedIdentifier(type.location, type));
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

