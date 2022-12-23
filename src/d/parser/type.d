module d.parser.type;

import d.ast.expression;
import d.ast.type;

import d.ir.expression;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.expression;
import d.parser.identifier;
import source.parserutil;

AstType parseType(ParseMode mode = ParseMode.Greedy)(ref TokenRange trange) {
	auto base = trange.parseBasicType();
	return trange.parseTypeSuffix!mode(base);
}

auto parseBasicType(ref TokenRange trange) {
	auto processQualifier(TypeQualifier qualifier)() {
		trange.popFront();

		if (trange.front.type == TokenType.OpenParen) {
			trange.popFront();
			auto type = trange.parseType();
			trange.match(TokenType.CloseParen);

			return type.qualify(qualifier);
		}

		return trange.parseType().qualify(qualifier);
	}

	switch (trange.front.type) with (TokenType) {
		// Types qualifiers
		case Const:
			return processQualifier!(TypeQualifier.Const)();

		case Immutable:
			return processQualifier!(TypeQualifier.Immutable)();

		case Inout:
			return processQualifier!(TypeQualifier.Mutable)();

		case Shared:
			return processQualifier!(TypeQualifier.Shared)();

		// Identified types
		case Identifier:
			return AstType.get(trange.parseIdentifier());

		case Dot:
			return AstType.get(trange.parseDotIdentifier());

		case Typeof:
			return trange.parseTypeof();

		case This:
			Location location = trange.front.location;
			auto thisExpression = new ThisExpression(location);

			trange.popFront();
			trange.match(Dot);

			return AstType
				.get(trange.parseQualifiedIdentifier(location, thisExpression));

		case Super:
			Location location = trange.front.location;
			auto superExpression = new SuperExpression(location);

			trange.popFront();
			trange.match(TokenType.Dot);

			return AstType.get(
				trange.parseQualifiedIdentifier(location, superExpression));

		// Basic types
		case Void:
			trange.popFront();
			return AstType.get(BuiltinType.Void);

		case Bool:
			trange.popFront();
			return AstType.get(BuiltinType.Bool);

		case Char:
			trange.popFront();
			return AstType.get(BuiltinType.Char);

		case Wchar:
			trange.popFront();
			return AstType.get(BuiltinType.Wchar);

		case Dchar:
			trange.popFront();
			return AstType.get(BuiltinType.Dchar);

		case Ubyte:
			trange.popFront();
			return AstType.get(BuiltinType.Ubyte);

		case Ushort:
			trange.popFront();
			return AstType.get(BuiltinType.Ushort);

		case Uint:
			trange.popFront();
			return AstType.get(BuiltinType.Uint);

		case Ulong:
			trange.popFront();
			return AstType.get(BuiltinType.Ulong);

		case Ucent:
			trange.popFront();
			return AstType.get(BuiltinType.Ucent);

		case Byte:
			trange.popFront();
			return AstType.get(BuiltinType.Byte);

		case Short:
			trange.popFront();
			return AstType.get(BuiltinType.Short);

		case Int:
			trange.popFront();
			return AstType.get(BuiltinType.Int);

		case Long:
			trange.popFront();
			return AstType.get(BuiltinType.Long);

		case Cent:
			trange.popFront();
			return AstType.get(BuiltinType.Cent);

		case Float:
			trange.popFront();
			return AstType.get(BuiltinType.Float);

		case Double:
			trange.popFront();
			return AstType.get(BuiltinType.Double);

		case Real:
			trange.popFront();
			return AstType.get(BuiltinType.Real);

		default:
			throw unexpectedTokenError(trange, "a type");
	}
}

/**
 * Parse typeof(...)
 */
private auto parseTypeof(ref TokenRange trange) {
	trange.match(TokenType.Typeof);
	trange.match(TokenType.OpenParen);

	scope(success) trange.match(TokenType.CloseParen);

	if (trange.front.type == TokenType.Return) {
		trange.popFront();
		return AstType.getTypeOfReturn();
	}

	return AstType.getTypeOf(trange.parseExpression());
}

/**
 * Parse *, [ ... ] and function/delegate types.
 */
AstType parseTypeSuffix(ParseMode mode)(ref TokenRange trange, AstType type) {
	while (true) {
		switch (trange.front.type) with (TokenType) {
			case Star:
				trange.popFront();
				type = type.getPointer();
				break;

			case OpenBracket:
				type = trange.parseBracket(type);
				break;

			case Function: {
				trange.popFront();

				import d.parser.declaration;
				import std.algorithm, std.array;
				bool isVariadic;
				auto params = trange.parseParameters(isVariadic)
				                    .map!(d => d.type).array();

				// TODO: parse postfix attributes.
				// TODO: ref return.
				type = FunctionAstType(
					Linkage.D, type.getParamType(ParamKind.Regular), params,
					isVariadic).getType();

				break;
			}

			case Delegate: {
				trange.popFront();

				import d.parser.declaration;
				import std.algorithm, std.array;
				bool isVariadic;
				auto params = trange.parseParameters(isVariadic)
				                    .map!(d => d.type).array();

				// TODO: fully typed delegates.
				auto ctx = AstType.get(BuiltinType.Void).getPointer()
				                  .getParamType(ParamKind.Regular);

				// TODO: parse postfix attributes and storage class.
				// TODO: ref return.
				type = FunctionAstType(
					Linkage.D, type.getParamType(ParamKind.Regular), ctx,
					params, isVariadic).getType();
			}

				break;

			static if (mode == ParseMode.Greedy) {
				case Dot:
					trange.popFront();

					// TODO: Duplicate function and pass location explicitely.
					type = AstType.get(trange
						.parseQualifiedIdentifier(trange.front.location, type));
					break;
			}

			default:
				return type;
		}
	}
}

private:
AstType parseBracket(ref TokenRange trange, AstType type) {
	trange.match(TokenType.OpenBracket);
	if (trange.front.type == TokenType.CloseBracket) {
		trange.popFront();
		return type.getSlice();
	}

	return trange.parseAmbiguous!((parsed) {
		trange.match(TokenType.CloseBracket);

		alias T = typeof(parsed);
		static if (is(T : AstType)) {
			return type.getMap(parsed);
		} else static if (is(T : AstExpression)) {
			return type.getArray(parsed);
		} else {
			return type.getBracket(parsed);
		}
	})();
}
