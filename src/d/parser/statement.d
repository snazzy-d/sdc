module d.parser.statement;

import d.ast.statement;
import d.ast.expression;

import d.parser.conditional;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;
import d.parser.util;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

Statement parseStatement(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	switch(tstream.peek.type) {
		case TokenType.OpenBrace :
			return parseBlock(tstream);
		
		case TokenType.If :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			
			auto then = parseStatement(tstream);
			
			if(tstream.peek.type == TokenType.Else) {
				tstream.get();
				auto elseStatement = parseStatement(tstream);
				
				location.spanTo(tstream.previous.location);
				
				return new IfElseStatement(location, condition, then, elseStatement);
			}
			
			location.spanTo(tstream.previous.location);
			return new IfStatement(location, condition, then);
		
		case TokenType.While :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			
			auto statement = parseStatement(tstream);
			
			location.spanTo(tstream.previous.location);
			return new WhileStatement(location, condition, statement);
		
		case TokenType.Do :
			tstream.get();
			
			auto statement = parseStatement(tstream);
			
			match(tstream, TokenType.While);
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			
			location.spanTo(match(tstream, TokenType.Semicolon).location);
			return new DoWhileStatement(location, condition, statement);
		
		case TokenType.For :
			tstream.get();
			
			match(tstream, TokenType.OpenParen);
			
			Statement init;
			if(tstream.peek.type == TokenType.Semicolon) {
				init = new BlockStatement(tstream.get().location, []);
			} else {
				init = parseStatement(tstream);
			}
			
			auto condition = parseExpression(tstream);
			match(tstream, TokenType.Semicolon);
			
			auto increment = parseExpression(tstream);
			match(tstream, TokenType.CloseParen);
			
			auto statement = parseStatement(tstream);
			
			location.spanTo(tstream.previous.location);
			return new ForStatement(location, init, condition, increment, statement);
		
		case TokenType.Foreach :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			
			// Hack hack hack HACK !
			while(tstream.peek.type != TokenType.Semicolon) tstream.get();
			
			match(tstream, TokenType.Semicolon);
			parseExpression(tstream);
			
			if(tstream.peek.type == TokenType.DoubleDot) {
				tstream.get();
				parseExpression(tstream);
			}
			
			match(tstream, TokenType.CloseParen);
			
			parseStatement(tstream);
			
			return null;
		
		case TokenType.Break :
			tstream.get();
			
			if(tstream.peek.type == TokenType.Identifier) tstream.get();
			
			location.spanTo(match(tstream, TokenType.Semicolon).location);
			
			return new BreakStatement(location);
		
		case TokenType.Continue :
			tstream.get();
			
			if(tstream.peek.type == TokenType.Identifier) tstream.get();
			
			location.spanTo(match(tstream, TokenType.Semicolon).location);
			
			return new ContinueStatement(location);
		
		case TokenType.Return :
			tstream.get();
			
			Expression value;
			if(tstream.peek.type != TokenType.Semicolon) {
				value = parseExpression(tstream);
			}
			
			location.spanTo(match(tstream, TokenType.Semicolon).location);
			return new ReturnStatement(location, value);
		
		case TokenType.Synchronized :
			tstream.get();
			if(tstream.peek.type == TokenType.OpenParen) {
				tstream.get();
				
				parseExpression(tstream);
				
				match(tstream, TokenType.CloseParen);
			}
			
			parseStatement(tstream);
			
			return null;
		
		case TokenType.Try :
			tstream.get();
			
			auto statement = parseStatement(tstream);
			
			CatchBlock[] catches;
			while(tstream.peek.type == TokenType.Catch) {
				auto catchLocation = tstream.get().location;
				
				if(tstream.peek.type == TokenType.OpenParen) {
					tstream.get();
					auto type = parseBasicType(tstream);
					string name;
					
					if(tstream.peek.type == TokenType.Identifier) {
						name = tstream.get().value;
					}
					
					match(tstream, TokenType.CloseParen);
					
					auto catchStatement = parseStatement(tstream);
					
					location.spanTo(tstream.previous.location);
					catches ~= new CatchBlock(location, type, name, catchStatement);
				} else {
					// TODO: handle final catches ?
					parseStatement(tstream);
					break;
				}
			}
			
			if(tstream.peek.type == TokenType.Finally) {
				tstream.get();
				auto finallyStatement = parseStatement(tstream);
				
				location.spanTo(tstream.previous.location);
				return new TryFinallyStatement(location, statement, [], finallyStatement);
			}
			
			location.spanTo(tstream.previous.location);
			return new TryStatement(location, statement, []);
		
		case TokenType.Throw :
			tstream.get();
			auto value = parseExpression(tstream);
			
			location.spanTo(match(tstream, TokenType.Semicolon).location);
			return new ThrowStatement(location, value);
		
		case TokenType.Mixin :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			parseExpression(tstream);
			match(tstream, TokenType.CloseParen);
			match(tstream, TokenType.Semicolon);
			break;
		
		case TokenType.Static :
			switch(tstream.lookahead(1).type) {
				case TokenType.If :
					return parseStaticIf!Statement(tstream);
				
				case TokenType.Assert :
					tstream.get();
					tstream.get();
					match(tstream, TokenType.OpenParen);
					
					parseArguments(tstream);
					
					match(tstream, TokenType.CloseParen);
					match(tstream, TokenType.Semicolon);
					
					return null;
				
				default :
					return parseDeclaration(tstream);
			}
		
		case TokenType.Version, TokenType.Debug :
			return parseVersion!Statement(tstream);
		
		default :
			if(isDeclaration(tstream)) {
				return parseDeclaration(tstream);
			} else {
				auto expression = parseExpression(tstream);
				match(tstream, TokenType.Semicolon);
				
				return expression;
			}
	}
	
	assert(0);
}

BlockStatement parseBlock(TokenStream tstream) {
	match(tstream, TokenType.OpenBrace);
	
	auto location = tstream.previous.location;
	
	Statement[] statements;
	
	while(tstream.peek.type != TokenType.CloseBrace) {
		statements ~= parseStatement(tstream);
	}
	
	location.spanTo(tstream.peek.location);
	
	tstream.get();
	
	return new BlockStatement(location, statements);
}

