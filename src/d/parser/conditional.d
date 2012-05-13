module d.parser.conditional;

import d.ast.conditional;
import d.ast.declaration;
import d.ast.statement;

import d.parser.declaration;
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
	
	switch(tstream.peek.type) {
		case TokenType.OpenParen :
			tstream.get();
			string versionId = match(tstream, TokenType.Identifier).value;
			match(tstream, TokenType.CloseParen);
			
			ItemType[] items;
			if(tstream.peek.type == TokenType.OpenBrace) {
				items = parseAggregate(tstream);
			} else {
				items = [parseDeclaration(tstream)];
			}
			
			if(tstream.peek.type == TokenType.Else) {
				tstream.get();
				
				ItemType[] elseItems;
				if(tstream.peek.type == TokenType.OpenBrace) {
					elseItems = parseAggregate(tstream);
				} else {
					elseItems = [parseDeclaration(tstream)];
				}
				
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

