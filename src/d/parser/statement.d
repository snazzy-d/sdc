module d.parser.statement;

import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.conditional;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;

Statement parseStatement(ref TokenRange trange) {
	auto location = trange.front.location;

	switch (trange.front.type) with (TokenType) {
		case OpenBrace:
			return trange.parseBlock();

		case Identifier:
			auto lookahead = trange.getLookahead();
			lookahead.popFront();

			if (lookahead.front.type == Colon) {
				goto ParseLabel;
			}

			// If it is not a labeled statement,
			// then it is a declaration or an expression.
			goto default;

		case If:
			trange.popFront();
			trange.match(OpenParen);
			auto condition = trange.parseExpression();
			trange.match(CloseParen);

			auto then = trange.parseStatement();

			Statement elseStatement;
			if (trange.front.type == Else) {
				trange.popFront();
				elseStatement = trange.parseStatement();
			}

			return new IfStatement(location.spanTo(trange.previous), condition,
			                       then, elseStatement);

		case While:
			trange.popFront();
			trange.match(OpenParen);
			auto condition = trange.parseExpression();

			trange.match(CloseParen);

			auto statement = trange.parseStatement();
			return new WhileStatement(location.spanTo(trange.previous),
			                          condition, statement);

		case Do:
			trange.popFront();

			auto statement = trange.parseStatement();

			trange.match(While);
			trange.match(OpenParen);
			auto condition = trange.parseExpression();

			trange.match(CloseParen);
			trange.match(Semicolon);

			return new DoWhileStatement(location.spanTo(trange.previous),
			                            condition, statement);

		case For:
			trange.popFront();

			trange.match(OpenParen);

			Statement init;
			if (trange.front.type != Semicolon) {
				init = trange.parseStatement();
			} else {
				trange.popFront();
			}

			AstExpression condition;
			if (trange.front.type != Semicolon) {
				condition = trange.parseExpression();
			}

			trange.match(Semicolon);

			AstExpression increment;
			if (trange.front.type != CloseParen) {
				increment = trange.parseExpression();
			}

			trange.match(CloseParen);

			auto statement = trange.parseStatement();
			return new ForStatement(location.spanTo(trange.previous), init,
			                        condition, increment, statement);

		case Foreach, ForeachReverse:
			bool reverse = (trange.front.type == ForeachReverse);
			trange.popFront();
			trange.match(OpenParen);

			ParamDecl parseForeachListElement() {
				auto elementLocation = trange.front.location;

				bool isRef = trange.front.type == Ref;
				if (isRef) {
					trange.popFront();
				}

				bool parseType = true;
				// If we have an idientifer, check if the type is implicit.
				if (trange.front.type == Identifier) {
					auto lookahead = trange.getLookahead();
					lookahead.popFront();
					if (lookahead.front.type == Comma
						    || lookahead.front.type == Semicolon) {
						parseType = false;
					}
				}

				auto type = parseType ? trange.parseType() : AstType.getAuto();
				auto name = trange.match(Identifier).name;

				return ParamDecl(
					elementLocation.spanTo(trange.previous),
					type.getParamType(
						isRef ? ParamKind.Ref : ParamKind.Regular),
					name,
					null,
				);
			}

			ParamDecl[] tupleElements = [parseForeachListElement()];
			while (trange.front.type == Comma) {
				trange.popFront();
				tupleElements ~= parseForeachListElement();
			}

			trange.match(Semicolon);
			auto iterrated = trange.parseExpression();

			bool isRange = trange.front.type == DotDot;

			AstExpression endOfRange;
			if (isRange) {
				trange.popFront();
				endOfRange = trange.parseExpression();
			}

			trange.match(CloseParen);

			auto statement = trange.parseStatement();
			location = location.spanTo(trange.previous);

			return isRange
				? new ForeachRangeStatement(location, tupleElements, iterrated,
				                            endOfRange, statement, reverse)
				: new ForeachStatement(location, tupleElements, iterrated,
				                       statement, reverse);

		case Return:
			trange.popFront();

			AstExpression value;
			if (trange.front.type != Semicolon) {
				value = trange.parseExpression();
			}

			trange.match(Semicolon);
			return new ReturnStatement(location.spanTo(trange.previous), value);

		case Break:
			trange.popFront();
			if (trange.front.type == Identifier) {
				trange.popFront();
			}

			trange.match(Semicolon);
			return new BreakStatement(location.spanTo(trange.previous));

		case Continue:
			trange.popFront();
			if (trange.front.type == Identifier) {
				trange.popFront();
			}

			trange.match(Semicolon);
			return new ContinueStatement(location.spanTo(trange.previous));

		case Switch:
			trange.popFront();
			trange.match(OpenParen);
			auto expression = trange.parseExpression();
			trange.match(CloseParen);

			auto statement = trange.parseStatement();
			return new SwitchStatement(location.spanTo(trange.previous),
			                           expression, statement);

		case Case:
			trange.popFront();
			AstExpression[] cases = trange.parseArguments();
			trange.match(Colon);

			Statement statement;
			if (trange.front.type != CloseBrace) {
				statement = trange.parseStatement();
			}

			return new CaseStatement(location.spanTo(trange.previous), cases,
			                         statement);

		case Default:

		ParseLabel:
			// Other labeled statement will jump here !
			auto label = trange.front.name;
			trange.popFront();
			trange.match(Colon);

			Statement statement;
			if (trange.front.type != CloseBrace) {
				statement = trange.parseStatement();
			}

			return new LabeledStatement(location.spanTo(trange.previous), label,
			                            statement);

		case Goto:
			trange.popFront();

			import source.name;
			Name label;
			switch (trange.front.type) {
				case Identifier:
				case Default:
				case Case:
					label = trange.front.name;
					trange.popFront();
					break;

				default:
					trange.match(Identifier);
			}

			trange.match(Semicolon);
			return new GotoStatement(location.spanTo(trange.previous), label);

		case Scope:
			trange.popFront();
			trange.match(OpenParen);

			auto name = trange.match(Identifier).name;

			import source.name;
			ScopeKind kind;
			if (name == BuiltinName!"exit") {
				kind = ScopeKind.Exit;
			} else if (name == BuiltinName!"success") {
				kind = ScopeKind.Success;
			} else if (name == BuiltinName!"failure") {
				kind = ScopeKind.Failure;
			} else {
				assert(
					0,
					name.toString(trange.context)
						~ " is not a valid scope identifier."
				);
			}

			trange.match(CloseParen);

			auto statement = trange.parseStatement();
			return new ScopeStatement(location.spanTo(trange.previous), kind,
			                          statement);

		case Assert:
			trange.popFront();
			trange.match(OpenParen);

			auto condition = trange.parseAssignExpression();
			AstExpression message;
			if (trange.front.type == Comma) {
				trange.popFront();
				message = trange.parseAssignExpression();

				// Trailing comma
				if (trange.front.type == Comma) {
					trange.popFront();
				}
			}

			trange.match(CloseParen);
			trange.match(Semicolon);

			return new AssertStatement(location.spanTo(trange.previous),
			                           condition, message);

		case Throw:
			trange.popFront();
			auto value = trange.parseExpression();

			trange.match(Semicolon);
			return new ThrowStatement(location.spanTo(trange.previous), value);

		case Try:
			trange.popFront();

			auto statement = trange.parseStatement();

			CatchBlock[] catches;
			while (trange.front.type == Catch) {
				auto cloc = trange.front.location;
				trange.popFront();

				if (trange.front.type == OpenParen) {
					trange.popFront();

					import d.parser.identifier;
					auto type = trange.parseIdentifier();

					import source.name;
					Name name;
					if (trange.front.type == Identifier) {
						name = trange.front.name;
						trange.popFront();
					}

					trange.match(CloseParen);

					auto catchStatement = trange.parseStatement();
					catches ~= CatchBlock(cloc.spanTo(trange.previous), type,
					                      name, catchStatement);
				} else {
					// TODO: handle final catches ?
					trange.parseStatement();
					assert(0, "Final catches not implemented");
				}
			}

			Statement finallyStatement;
			if (trange.front.type == Finally) {
				trange.popFront();
				finallyStatement = trange.parseStatement();
			}

			return new TryStatement(location.spanTo(trange.previous), statement,
			                        catches, finallyStatement);

		case Synchronized:
			trange.popFront();
			if (trange.front.type == OpenParen) {
				trange.popFront();
				trange.parseExpression();
				trange.match(CloseParen);
			}

			auto statement = trange.parseStatement();
			return new SynchronizedStatement(location.spanTo(trange.previous),
			                                 statement);

		case Mixin:
			trange.popFront();
			trange.match(OpenParen);

			auto expr = trange.parseAssignExpression();

			// To deambiguate vs TokenType.Mixin.
			import d.ast.conditional : Mixin;

			trange.match(CloseParen);
			if (trange.front.type == Semicolon) {
				// mixin(expr); is a statement.
				trange.popFront();
				return
					new Mixin!Statement(location.spanTo(trange.previous), expr);
			}

			expr =
				new Mixin!AstExpression(location.spanTo(trange.previous), expr);
			return trange.parseStatementSuffix(expr);

		case Static:
			auto lookahead = trange.getLookahead();
			lookahead.popFront();

			switch (lookahead.front.type) {
				case If:
					return trange.parseStaticIf!Statement();

				case Assert:
					return trange.parseStaticAssert!Statement();

				default:
					auto declaration = trange.parseDeclaration();
					return new DeclarationStatement(declaration);
			}

		case Version:
			return trange.parseVersion!Statement();

		case Debug:
			return trange.parseDebug!Statement();

		default:
			return trange.parseAmbiguousStatement();
	}

	assert(0);
}

BlockStatement parseBlock(ref TokenRange trange) {
	Location location = trange.front.location;

	trange.match(TokenType.OpenBrace);

	Statement[] statements;

	while (trange.front.type != TokenType.CloseBrace) {
		statements ~= trange.parseStatement();
	}

	trange.popFront();
	return new BlockStatement(location.spanTo(trange.previous), statements);
}
