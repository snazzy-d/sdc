module source.jsonlexer;

import source.context;
import source.location;

enum TokenType {
	// sdfmt off
	Invalid = 0,

	Begin,
	End,

	// Comments
	Comment,

	// Literals
	StringLiteral,
	IntegerLiteral,
	FloatLiteral,

	// Identifier
	Identifier,

	// Keywords
	Null, True, False,

	// Operators.
	OpenParen,    // (
	CloseParen,   // )
	OpenBracket,  // [
	CloseBracket, // ]
	OpenBrace,    // {
	CloseBrace,   // }
	Comma,        // ,
	Colon,        // :
	// sdfmt on
}

struct Token {
	TokenType type;

	import source.name;
	Name name;

	import source.location;
	Location location;

	@property
	Name error() const {
		return name;
	}

	static getError(Location location, Name message) {
		Token t;
		t.type = TokenType.Invalid;
		t.name = message;
		t.location = location;

		return t;
	}

	static getBegin(Location location) {
		Token t;
		t.type = TokenType.Begin;
		t.location = location;

		return t;
	}

	static getEnd(Location location) {
		Token t;
		t.type = TokenType.End;
		t.name = BuiltinName!"\0";
		t.location = location;

		return t;
	}

	static getComment(string s)(Location location) {
		Token t;
		t.type = TokenType.Comment;
		t.name = BuiltinName!s;
		t.location = location;

		return t;
	}

	static getStringLiteral(Location location, Name value) {
		Token t;
		t.type = TokenType.StringLiteral;
		t.name = value;
		t.location = location;

		return t;
	}

	static getIntegerLiteral(Location location, ulong value) {
		Token t;
		t.type = TokenType.IntegerLiteral;
		t.location = location;

		return t;
	}

	static getFloatLiteral(Location location, double value) {
		Token t;
		t.type = TokenType.FloatLiteral;
		t.location = location;

		return t;
	}

	static getIdentifier(Location location, Name name) {
		Token t;
		t.type = TokenType.Identifier;
		t.name = name;
		t.location = location;

		return t;
	}

	static getKeyword(string kw)(Location location) {
		enum Type = JsonLexer.KeywordMap[kw];

		Token t;
		t.type = Type;
		t.name = BuiltinName!kw;
		t.location = location;

		return t;
	}

	static getOperator(string op)(Location location) {
		enum Type = JsonLexer.OperatorMap[op];

		Token t;
		t.type = Type;
		t.name = BuiltinName!op;
		t.location = location;

		return t;
	}

	import source.context;
	string toString(Context context) {
		return (type >= TokenType.Identifier)
			? name.toString(context)
			: location.getFullLocation(context).getSlice();
	}
}

auto lex(Position base, Context context) {
	auto lexer = JsonLexer();

	lexer.context = context;
	lexer.base = base;
	lexer.previous = base;
	lexer.content = base.getFullPosition(context).getSource().getContent();

	auto beginLocation = Location(base, base.getWithOffset(lexer.index));
	lexer.t = Token.getBegin(beginLocation);

	return lexer;
}

struct JsonLexer {
	enum BaseMap = () {
		auto ret = [
			// sdfmt off
			// Comments
			"//" : "?Comment",
			"/*" : "?Comment",
			"/+" : "?Comment",

			// Integer literals.
			"0b" : "lexNumeric",
			"0B" : "lexNumeric",
			"0x" : "lexNumeric",
			"0X" : "lexNumeric",

			// String literals.
			`"` : "lexString",
			"'" : "lexString",
			// sdfmt on
		];

		foreach (i; 0 .. 10) {
			import std.conv;
			ret[to!string(i)] = "lexNumeric";
		}

		return ret;
	}();

	enum KeywordMap = [
		// sdfmt off
		"null"  : TokenType.Null,
		"true"  : TokenType.True,
		"false" : TokenType.False,
		// sdfmt on
	];

	enum OperatorMap = [
		// sdfmt off
		"("  : TokenType.OpenParen,
		")"  : TokenType.CloseParen,
		"["  : TokenType.OpenBracket,
		"]"  : TokenType.CloseBracket,
		"{"  : TokenType.OpenBrace,
		"}"  : TokenType.CloseBrace,
		","  : TokenType.Comma,
		":"  : TokenType.Colon,
		"\0" : TokenType.End,
		// sdfmt on
	];

	import source.lexbase;
	mixin LexBaseImpl!(Token, BaseMap, KeywordMap, OperatorMap);

	import source.lexnumeric;
	mixin LexNumericImpl!Token;

	import source.lexstring;
	mixin LexStringImpl!Token;
}

unittest {
	auto context = new Context();

	auto testlexer(string s) {
		import source.name;
		auto base = context.registerMixin(Location.init, s ~ '\0');
		return lex(base, context);
	}

	import source.parserutil;

	{
		auto lex = testlexer("");
		lex.match(TokenType.Begin);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("null(aa[{]true})false");
		lex.match(TokenType.Begin);
		lex.match(TokenType.Null);
		lex.match(TokenType.OpenParen);

		auto t = lex.front;
		assert(t.type == TokenType.Identifier);
		assert(t.toString(context) == "aa");

		lex.popFront();
		lex.match(TokenType.OpenBracket);
		lex.match(TokenType.OpenBrace);
		lex.match(TokenType.CloseBracket);
		lex.match(TokenType.True);
		lex.match(TokenType.CloseBrace);
		lex.match(TokenType.CloseParen);
		lex.match(TokenType.False);

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`"""foobar"'''balibalo'"\""'"'"'"`);
		lex.match(TokenType.Begin);

		foreach (expected;
			[`""`, `"foobar"`, `''`, `'balibalo'`, `"\""`, `'"'`, `"'"`]
		) {
			auto t = lex.front;

			assert(t.type == TokenType.StringLiteral);
			assert(t.toString(context) == expected);
			lex.popFront();
		}

		assert(lex.front.type == TokenType.End);
	}

	// Check unterminated strings.
	{
		auto lex = testlexer(`"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;
		assert(t.type == TokenType.Invalid);
	}

	{
		auto lex = testlexer(`"\`);
		lex.match(TokenType.Begin);

		auto t = lex.front;
		assert(t.type == TokenType.Invalid);
	}

	{
		auto lex = testlexer(`'`);
		lex.match(TokenType.Begin);

		auto t = lex.front;
		assert(t.type == TokenType.Invalid);
	}

	{
		auto lex = testlexer(`'\`);
		lex.match(TokenType.Begin);

		auto t = lex.front;
		assert(t.type == TokenType.Invalid);
	}
}
