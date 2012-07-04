module d.parser.conditional;

import d.ast.conditional;
import d.ast.declaration;
import d.ast.statement;

import d.parser.declaration;
import d.parser.expression;
import d.parser.statement;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Parse Version Declaration
 */
auto parseVersion(ItemType)(TokenStream tstream) if(is(ItemType == Statement) || is(ItemType == Declaration)) {
	return parseconditionalBlock!(true, ItemType)(tstream);
}

/**
 * Parse Debug Declaration
 */
auto parseDebug(ItemType)(TokenStream tstream) if(is(ItemType == Statement) || is(ItemType == Declaration)) {
	return parseconditionalBlock!(false, ItemType)(tstream);
}

private ItemType parseconditionalBlock(bool isVersion, ItemType)(TokenStream tstream) {
	static if(isVersion) {
		alias TokenType.Version conditionalTokenType;
		alias Version ConditionalType;
		alias VersionElse ConditionalElseType;
		alias VersionDefinition DefinitionType;
	} else {
		alias TokenType.Debug conditionalTokenType;
		alias Debug ConditionalType;
		alias DebugElse ConditionalElseType;
		alias DebugDefinition DefinitionType;
	}
	
	auto location = match(tstream, conditionalTokenType).location;
	
	// TODO: refactor.
	switch(tstream.peek.type) {
		case TokenType.OpenParen :
			tstream.get();
			string versionId;
			switch(tstream.peek.type) {
				case TokenType.Identifier :
					versionId = match(tstream, TokenType.Identifier).value;
					break;
				
				case TokenType.Unittest :
					static if(isVersion) {
						tstream.get();
						versionId = "unittest";
						break;
					} else {
						// unittest isn't a special token for debug.
						goto default;
					}
					
				default :
					assert(0);
			}
			
			match(tstream, TokenType.CloseParen);
			
			ItemType[] items = parseItems!ItemType(tstream);
			
			if(tstream.peek.type == TokenType.Else) {
				tstream.get();
				
				ItemType[] elseItems = parseItems!ItemType(tstream);
				
				return new ConditionalElseType!ItemType(location, versionId, items, elseItems);
			} else {
				return new ConditionalType!ItemType(location, versionId, items);
			}
		
		case TokenType.Assign :
			tstream.get();
			string versionId = match(tstream, TokenType.Identifier).value;
			match(tstream, TokenType.Semicolon);
			
			return new DefinitionType(location, versionId);
		
		default :
			// TODO: error.
			assert(0);
	}
}

/**
 * Parse static if.
 */
ItemType parseStaticIf(ItemType)(TokenStream tstream) if(is(ItemType == Statement) || is(ItemType == Declaration)) {
	auto location = match(tstream, TokenType.Static).location;
	match(tstream, TokenType.If);
	match(tstream, TokenType.OpenParen);
	
	auto condition = parseExpression(tstream);
	
	match(tstream, TokenType.CloseParen);
	
	ItemType[] items = parseItems!ItemType(tstream);
	
	if(tstream.peek.type == TokenType.Else) {
		tstream.get();
		
		ItemType[] elseItems = parseItems!ItemType(tstream);
		
		return new StaticIfElse!ItemType(location, condition, items, elseItems);
	} else {
		return new StaticIf!ItemType(location, condition, items);
	}
}

/**
 * Parse the content of the conditionnal depending on if it is statement or declaration that are expected.
 */
private auto parseItems(ItemType)(TokenStream tstream) {
	ItemType[] items;
	if(tstream.peek.type == TokenType.OpenBrace) {
		static if(is(ItemType == Statement)) {
			tstream.get();
			
			do {
				items ~= parseStatement(tstream);
			} while(tstream.peek.type != TokenType.CloseBrace);
			
			tstream.get();
		} else {
			items = parseAggregate(tstream);
		}
	} else {
		static if(is(ItemType == Statement)) {
			items = [parseStatement(tstream)];
		} else {
			items = [parseDeclaration(tstream)];
		}
	}
	
	return items;
}

