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
private:
	import util.bitfields;
	enum TypeSize = EnumSize!TokenType;
	enum ExtraBits = 8 * uint.sizeof - TypeSize;

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		TokenType, "_type", TypeSize,
		uint, "_extra", ExtraBits,
		// sdfmt on
	));

	union {
		import source.name;
		Name _name;

		uint _base;
	}

	import source.location;
	Location _location;

	static assert(Token.sizeof == 4 * uint.sizeof);

public:
	@property
	TokenType type() const {
		return _type;
	}

	@property
	Location location() const {
		return _location;
	}

	@property
	Name name() const in(type >= TokenType.Identifier) {
		return _name;
	}

	@property
	Name error() const in(type == TokenType.Invalid) {
		return _name;
	}

	@property
	Name decodedString() const in(type == TokenType.StringLiteral) {
		return _name;
	}

	import source.packedint;
	alias PackedInt = source.packedint.PackedInt!ExtraBits;

	PackedInt packedInt() const in(type == TokenType.IntegerLiteral) {
		return PackedInt.recompose(_base, _extra);
	}

	import source.packedfloat;
	alias PackedFloat = source.packedfloat.PackedFloat!ExtraBits;

	PackedFloat packedFloat() const in(type == TokenType.FloatLiteral) {
		return PackedFloat.recompose(_base, _extra);
	}

	import source.context;
	string toString(Context context) {
		return (type >= TokenType.Identifier)
			? name.toString(context)
			: location.getFullLocation(context).getSlice();
	}

public:
	static getError(Location location, Name message) {
		Token t;
		t._type = TokenType.Invalid;
		t._name = message;
		t._location = location;

		return t;
	}

	static getBegin(Location location) {
		Token t;
		t._type = TokenType.Begin;
		t._location = location;

		return t;
	}

	static getEnd(Location location) {
		Token t;
		t._type = TokenType.End;
		t._name = BuiltinName!"\0";
		t._location = location;

		return t;
	}

	static getComment(string s)(Location location) {
		Token t;
		t._type = TokenType.Comment;
		t._name = BuiltinName!s;
		t._location = location;

		return t;
	}

	static getStringLiteral(Location location, Name value) {
		Token t;
		t._type = TokenType.StringLiteral;
		t._name = value;
		t._location = location;

		return t;
	}

	static getIntegerLiteral(Location location, PackedInt value) {
		Token t;
		t._type = TokenType.IntegerLiteral;
		t._location = location;

		t._base = value.base;
		t._extra = value.extra;

		return t;
	}

	static getFloatLiteral(Location location, PackedFloat value) {
		Token t;
		t._type = TokenType.FloatLiteral;
		t._location = location;

		t._base = value.base;
		t._extra = value.extra;

		return t;
	}

	static getIdentifier(Location location, Name name) {
		Token t;
		t._type = TokenType.Identifier;
		t._name = name;
		t._location = location;

		return t;
	}

	static getKeyword(string kw)(Location location) {
		enum Type = JsonLexer.KeywordMap[kw];

		Token t;
		t._type = Type;
		t._name = BuiltinName!kw;
		t._location = location;

		return t;
	}

	static getOperator(string op)(Location location) {
		enum Type = JsonLexer.OperatorMap[op];

		Token t;
		t._type = Type;
		t._name = BuiltinName!op;
		t._location = location;

		return t;
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

		return registerNumericPrefixes(ret);
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
