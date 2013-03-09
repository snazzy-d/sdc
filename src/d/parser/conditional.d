module d.parser.conditional;

import d.ast.conditional;
import d.ast.declaration;
import d.ast.statement;

import d.parser.base;
import d.parser.declaration;
import d.parser.expression;
import d.parser.statement;

/**
 * Parse Version Declaration
 */
auto parseVersion(ItemType, TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange && (is(ItemType == Statement) || is(ItemType == Declaration))) {
	return trange.parseconditionalBlock!(true, ItemType)();
}

/**
 * Parse Debug Declaration
 */
auto parseDebug(ItemType, TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange && (is(ItemType == Statement) || is(ItemType == Declaration))) {
	return trange.parseconditionalBlock!(false, ItemType)();
}

private ItemType parseconditionalBlock(bool isVersion, ItemType, TokenRange)(ref TokenRange trange) {
	static if(isVersion) {
		alias TokenType.Version conditionalTokenType;
		alias Version!ItemType ConditionalType;
		alias VersionDefinition!ItemType DefinitionType;
	} else {
		alias TokenType.Debug conditionalTokenType;
		alias Debug!ItemType ConditionalType;
		alias DebugDefinition!ItemType DefinitionType;
	}
	
	Location location = trange.front.location;
	trange.match(conditionalTokenType);
	
	// TODO: refactor.
	switch(trange.front.type) {
		case TokenType.OpenParen :
			trange.popFront();
			string versionId;
			switch(trange.front.type) {
				case TokenType.Identifier :
					versionId = trange.front.value;
					trange.match(TokenType.Identifier);
					
					break;
				
				case TokenType.Unittest :
					static if(isVersion) {
						trange.popFront();
						versionId = "unittest";
						break;
					} else {
						// unittest isn't a special token for debug.
						goto default;
					}
					
				default :
					assert(0);
			}
			
			trange.match(TokenType.CloseParen);
			
			ItemType[] items = trange.parseItems!ItemType();
			ItemType[] elseItems;
			
			if(trange.front.type == TokenType.Else) {
				trange.popFront();
				
				elseItems = trange.parseItems!ItemType();
			}
			
			return new ConditionalType(location, versionId, items, elseItems);
		
		case TokenType.Assign :
			trange.popFront();
			string versionId = trange.front.value;
			trange.match(TokenType.Identifier);
			trange.match(TokenType.Semicolon);
			
			return new DefinitionType(location, versionId);
		
		default :
			// TODO: error.
			assert(0);
	}
}

/**
 * Parse static if.
 */
ItemType parseStaticIf(ItemType, TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange && (is(ItemType == Statement) || is(ItemType == Declaration))) {
	auto location = trange.front.location;
	
	trange.match(TokenType.Static);
	trange.match(TokenType.If);
	trange.match(TokenType.OpenParen);
	
	auto condition = trange.parseExpression();
	
	trange.match(TokenType.CloseParen);
	
	ItemType[] items = trange.parseItems!ItemType();
	
	if(trange.front.type == TokenType.Else) {
		trange.popFront();
		
		ItemType[] elseItems = trange.parseItems!ItemType();
		
		return new StaticIfElse!ItemType(location, condition, items, elseItems);
	} else {
		return new StaticIf!ItemType(location, condition, items);
	}
}

/**
 * Parse the content of the conditionnal depending on if it is statement or declaration that are expected.
 */
private auto parseItems(ItemType, TokenRange)(ref TokenRange trange) {
	ItemType[] items;
	if(trange.front.type == TokenType.OpenBrace) {
		static if(is(ItemType == Statement)) {
			trange.popFront();
			
			do {
				items ~= trange.parseStatement();
			} while(trange.front.type != TokenType.CloseBrace);
			
			trange.popFront();
		} else {
			items = trange.parseAggregate();
		}
	} else {
		static if(is(ItemType == Statement)) {
			items = [trange.parseStatement()];
		} else {
			items = [trange.parseDeclaration()];
		}
	}
	
	return items;
}

/**
 * Parse mixins.
 */
auto parseMixin(ItemType, TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange && is(Mixin!ItemType)) {
	auto location = trange.front.location;
	
	trange.match(TokenType.Mixin);
	trange.match(TokenType.OpenParen);
	
	auto expression = trange.parseExpression();
	
	trange.match(TokenType.CloseParen);
	location.spanTo(trange.front.location);
	
	trange.match(TokenType.Semicolon);
	return new Mixin!ItemType(location, expression);
}

