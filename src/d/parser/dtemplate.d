module d.parser.dtemplate;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;

auto parseTemplate(ref TokenRange trange, StorageClass stc) {
	auto location = trange.front.location;
	trange.match(TokenType.Template);

	auto name = trange.match(TokenType.Identifier).name;

	auto parameters = trange.parseTemplateParameters();
	auto declarations = trange.parseAggregate();

	return new TemplateDeclaration(location.spanTo(trange.previous), stc, name,
	                               parameters, declarations);
}

auto parseConstraint(ref TokenRange trange) {
	trange.match(TokenType.If);
	trange.match(TokenType.OpenParen);

	trange.parseExpression();

	trange.match(TokenType.CloseParen);
}

auto parseTemplateParameters(ref TokenRange trange) {
	trange.match(TokenType.OpenParen);

	AstTemplateParameter[] parameters;
	while (trange.front.type != TokenType.CloseParen) {
		parameters ~= trange.parseTemplateParameter();

		if (!trange.popOnMatch(TokenType.Comma)) {
			break;
		}
	}

	trange.match(TokenType.CloseParen);
	return parameters;
}

private AstTemplateParameter parseTemplateParameter(ref TokenRange trange) {
	switch (trange.front.type) with (TokenType) {
		case Identifier:
			auto lookahead = trange.getLookahead();
			lookahead.popFront();
			switch (lookahead.front.type) {
				// Identifier followed by ":", "=", "," or ")" are type parameters.
				case Colon, Equal, Comma, CloseParen:
					return trange.parseTypeParameter();

				case DotDotDot:
					auto name = trange.front.name;
					auto location = lookahead.front.location;

					import std.range;
					trange.popFrontN(2);
					return new AstTupleTemplateParameter(location, name);

				default:
					// We probably have a value parameter (or an error).
					return trange.parseValueParameter();
			}

		case Alias:
			return trange.parseAliasParameter();

		case This:
			auto location = trange.front.location;
			trange.popFront();

			auto name = trange.match(Identifier).name;

			return new AstThisTemplateParameter(
				location.spanTo(trange.previous), name);

		default:
			// We probably have a value parameter (or an error).
			return trange.parseValueParameter();
	}
}

private auto parseTypeParameter(ref TokenRange trange) {
	auto location = trange.front.location;
	auto name = trange.match(TokenType.Identifier).name;

	AstType defaultType;
	switch (trange.front.type) with (TokenType) {
		case Colon:
			trange.popFront();
			auto specialization = trange.parseType();

			if (trange.front.type == Equal) {
				trange.popFront();
				defaultType = trange.parseType();
			}

			return new AstTypeTemplateParameter(
				location.spanTo(trange.previous), name, specialization,
				defaultType);

		case Equal:
			trange.popFront();
			defaultType = trange.parseType();

			goto default;

		default:
			location = location.spanTo(trange.previous);
			auto specialization =
				AstType.get(new BasicIdentifier(location, name));

			return new AstTypeTemplateParameter(location, name, specialization,
			                                    defaultType);
	}
}

private auto parseValueParameter(ref TokenRange trange) {
	auto location = trange.front.location;

	auto type = trange.parseType();
	auto name = trange.match(TokenType.Identifier).name;

	AstExpression defaultValue;
	if (trange.front.type == TokenType.Equal) {
		trange.popFront();
		switch (trange.front.type) with (TokenType) {
			case __File__, __Line__:
				trange.popFront();
				break;

			default:
				defaultValue = trange.parseAssignExpression();
		}
	}

	return new AstValueTemplateParameter(location.spanTo(trange.previous), name,
	                                     type, defaultValue);
}

private AstTemplateParameter parseAliasParameter(ref TokenRange trange) {
	auto location = trange.front.location;
	trange.match(TokenType.Alias);

	bool isTyped = false;
	if (trange.front.type != TokenType.Identifier) {
		isTyped = true;
	} else {
		// Identifier followed by ":", "=", "," or ")" are untyped alias parameters.
		auto lookahead = trange.getLookahead();
		lookahead.popFront();
		auto nextType = lookahead.front.type;
		switch (lookahead.front.type) with (TokenType) {
			case Colon, Equal, Comma, CloseParen:
				break;

			default:
				isTyped = true;
				break;
		}
	}

	if (isTyped) {
		auto type = trange.parseType();
		auto name = trange.match(TokenType.Identifier).name;

		return new AstTypedAliasTemplateParameter(
			location.spanTo(trange.previous), name, type);
	} else {
		auto name = trange.match(TokenType.Identifier).name;
		return new AstAliasTemplateParameter(location.spanTo(trange.previous),
		                                     name);
	}
}

auto parseTemplateArguments(ref TokenRange trange) {
	AstTemplateArgument[] arguments;

	switch (trange.front.type) with (TokenType) {
		case OpenParen:
			trange.popFront();

			while (trange.front.type != CloseParen) {
				import d.parser.ambiguous;
				arguments ~=
					trange.parseAmbiguous!(p => AstTemplateArgument(p))();

				if (!trange.popOnMatch(TokenType.Comma)) {
					break;
				}
			}

			trange.match(CloseParen);
			break;

		case Identifier:
			auto identifier =
				new BasicIdentifier(trange.front.location, trange.front.name);
			arguments = [AstTemplateArgument(identifier)];

			trange.popFront();
			break;

		case True, False, Null, IntegerLiteral, StringLiteral, CharacterLiteral,
		     FloatLiteral, __File__, __Line__:
			arguments = [AstTemplateArgument(trange.parsePrimaryExpression())];
			break;

			/+
		case This :
			// This can be passed as alias parameter.
		+/

		default:
			arguments = [AstTemplateArgument(trange.parseBasicType())];
			break;
	}

	return arguments;
}
