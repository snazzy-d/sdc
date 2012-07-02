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
ItemType parseVersion(ItemType)(TokenStream tstream) if(is(ItemType == Statement) || is(ItemType == Declaration)) {
	auto conditionalType = TokenType.Version;
	
	// TODO: handle debug properly.
	if(tstream.peek.type == TokenType.Debug) {
		conditionalType = TokenType.Debug;
	}
	
	auto location = match(tstream, conditionalType).location;
	
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
					// version unittest don't exist for debug
					if(conditionalType == TokenType.Debug) goto default;
					
					tstream.get();
					versionId = "unittest";
					break;
				
				default :
					assert(0);
			}
			
			match(tstream, TokenType.CloseParen);
			
			ItemType[] items = parseItems!ItemType(tstream);
			
			if(tstream.peek.type == TokenType.Else) {
				tstream.get();
				
				ItemType[] elseItems = parseItems!ItemType(tstream);
				
				return new VersionElse!ItemType(location, versionId, items, elseItems);
			} else {
				return new Version!ItemType(location, versionId, items);
			}
		
		case TokenType.Assign :
			tstream.get();
			string versionId = match(tstream, TokenType.Identifier).value;
			match(tstream, TokenType.Semicolon);
			
			return new VersionDefinition(location, versionId);
		
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
private auto parseItems(ItemType)(TokenStream tstream) if(is(ItemType == Statement) || is(ItemType == Declaration)) {
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

