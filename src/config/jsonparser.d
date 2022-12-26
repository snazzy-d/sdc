module config.jsonparser;

import source.jsonlexer;
import source.parserutil;

import config.value;

Value parseJSON(ref JsonLexer lexer) {
	lexer.match(TokenType.Begin);

	auto ret = lexer.parseJsonValue();

	if (lexer.front.type != TokenType.End) {
		// There are leftovers, error?
	}

	return ret;
}

unittest {
	import source.context;
	auto context = new Context();

	auto testJSON(string s) {
		import source.location;
		auto base = context.registerMixin(Location.init, s ~ '\0');
		auto lexer = lex(base, context);
		return lexer.parseJSON();
	}

	Value[] emptyArray;
	Value[string] emptyObject;

	assert(testJSON("null") == null);
	assert(testJSON("true") == true);
	assert(testJSON("false") == false);
	assert(testJSON(`""`) == "");
	assert(testJSON(`''`) == "");
	assert(testJSON(`"pouic"`) == "pouic");
	assert(testJSON(`'"'`) == "\"");
	assert(testJSON(`0`) == 0);
	assert(testJSON(`1`) == 1);
	assert(testJSON(`0x42`) == 0x42);
	assert(testJSON(`0b10101`) == 21);
	assert(testJSON(`[]`) == emptyArray);
	assert(testJSON(`[true, false]`) == [true, false]);
	assert(testJSON(`["foo", 'bar']`) == ["foo", "bar"]);
	assert(testJSON(`["fizz", 'buzz',]`) == ["fizz", "buzz"]);
	assert(testJSON(`["Dave", null]`) == [Value("Dave"), Value(null)]);
	assert(testJSON(`{}`) == emptyObject);

	assert(testJSON(`{foo: true, bar: false}`) == ["foo": true, "bar": false]);
	assert(testJSON(`{x: true, "y": false, 'z': null}`)
		== ["x": Value(true), "y": Value(false), "z": Value(null)]);
}

Value parseJsonValue(ref JsonLexer lexer) {
	auto t = lexer.front;

	switch (t.type) with (TokenType) {
		case Null:
			lexer.popFront();
			return Value(null);

		case True:
			lexer.popFront();
			return Value(true);

		case False:
			lexer.popFront();
			return Value(false);

		case StringLiteral:
			lexer.popFront();
			return Value(t.decodedString.toString(lexer.context));

		case IntegerLiteral:
			lexer.popFront();
			return Value(t.packedInt.toInt(lexer.context));

		case FloatLiteral:
			assert(0, "Not implemented");

		case OpenBracket:
			return lexer.parseJsonArray();

		case OpenBrace:
			return lexer.parseJsonObject();

		default:
			throw unexpectedTokenError(lexer, "a JSON value");
	}
}

Value parseJsonArray(ref JsonLexer lexer) {
	lexer.match(TokenType.OpenBracket);

	Value[] values;
	while (lexer.front.type != TokenType.CloseBracket) {
		values ~= lexer.parseJsonValue();
		if (!lexer.popOnMatch(TokenType.Comma)) {
			break;
		}
	}

	lexer.match(TokenType.CloseBracket);
	return Value(values);
}

Value parseJsonObject(ref JsonLexer lexer) {
	lexer.match(TokenType.OpenBrace);

	Value[string] values;
	while (lexer.front.type != TokenType.CloseBrace) {
		auto t = lexer.front;
		auto location = t.location;
		auto type = t.type;

		if (type != TokenType.Identifier && type != TokenType.StringLiteral) {
			import source.exception;
			throw new CompileException(location,
			                           "Expected an identifier or a string");
		}

		auto name = type == TokenType.Identifier ? t.name : t.decodedString;
		auto key = name.toString(lexer.context);

		lexer.popFront();
		lexer.match(TokenType.Colon);

		values[key] = lexer.parseJsonValue();
		if (!lexer.popOnMatch(TokenType.Comma)) {
			break;
		}
	}

	lexer.match(TokenType.CloseBrace);
	return Value(values);
}
