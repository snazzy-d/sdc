module source.dlexer;

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
	CharacterLiteral,
	IntegerLiteral,
	FloatLiteral,

	// Identifier
	Identifier,

	// Keywords
	Abstract, Alias, Align, Asm, Assert, Auto,
	Bool, Break, Byte,
	Case, Cast, Catch, Cdouble, Cent, Cfloat, Char,
	Class, Const, Continue, Creal,
	Dchar, Debug, Default, Delegate, Delete,
	Deprecated, Do, Double,
	Else, Enum, Export, Extern,
	False, Final, Finally, Float, For, Foreach,
	ForeachReverse, Function,
	Goto,
	Idouble, If, Ifloat, Immutable, Import, In,
	Inout, Int, Interface, Invariant, Ireal, Is,
	Lazy, Long,
	Macro, Mixin, Module,
	New, Nothrow, Null,
	Out, Override,
	Package, Pragma, Private, Protected, Public, Pure,
	Real, Ref, Return,
	Scope, Shared, Short, Static, Struct, Super,
	Switch, Synchronized,
	Template, This, Throw, True, Try, Typedef,
	Typeid, Typeof,
	Ubyte, Ucent, Uint, Ulong, Union, Unittest, Ushort,
	Version, Void, Volatile,
	Wchar, While, With,
	__File__, __Line__, __Gshared, __Traits, __Vector, __Parameters,

	// Operators.
	Slash,              // /
	SlashEqual,         // /=
	Dot,                // .
	DotDot,             // ..
	DotDotDot,          // ...
	Ampersand,          // &
	AmpersandEqual,     // &=
	AmpersandAmpersand, // &&
	Pipe,               // |
	PipeEqual,          // |=
	PipePipe,           // ||
	Minus,              // -
	MinusEqual,         // -=
	MinusMinus,         // --
	Plus,               // +
	PlusEqual,          // +=
	PlusPlus,           // ++
	SmallerThan,        // <
	SmallerEqual,       // <=
	LessLess,           // <<
	LessLessEqual,      // <<=
	LessMore,           // <>
	LessMoreEqual,      // <>=
	GreaterThan,        // >
	GreaterEqual,       // >=
	MoreMoreEqual,      // >>=
	MoreMoreMoreEqual,  // >>>=
	MoreMore,           // >>
	MoreMoreMore,       // >>>
	Bang,               // !
	BangEqual,          // !=
	BangLessMore,       // !<>
	BangLessMoreEqual,  // !<>=
	BangLess,           // !<
	BangLessEqual,      // !<=
	BangMore,           // !>
	BangMoreEqual,      // !>=
	OpenParen,          // (
	CloseParen,         // )
	OpenBracket,        // [
	CloseBracket,       // ]
	OpenBrace,          // {
	CloseBrace,         // }
	QuestionMark,       // ?
	Comma,              // ,
	Semicolon,          // ;
	Colon,              // :
	Dollar,             // $
	Equal,              // =
	EqualEqual,         // ==
	Star,               // *
	StarEqual,          // *=
	Percent,            // %
	PercentEqual,       // %=
	Caret,              // ^
	CaretEqual,         // ^=
	CaretCaret,         // ^^
	CaretCaretEqual,    // ^^=
	Tilde,              // ~
	TildeEqual,         // ~=
	At,                 // @
	FatArrow,           // =>
	Hash,               // #
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

		import source.decodedchar;
		DecodedChar _decodedChar;

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
	DecodedChar decodedChar() const in(type == TokenType.CharacterLiteral) {
		return _decodedChar;
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

	static getBegin(Location location, Name name) {
		Token t;
		t._type = TokenType.Begin;
		t._name = name;
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

	static getCharacterLiteral(Location location, DecodedChar value) {
		Token t;
		t._type = TokenType.CharacterLiteral;
		t._decodedChar = value;
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
		enum Type = DLexer.KeywordMap[kw];

		Token t;
		t._type = Type;
		t._name = BuiltinName!kw;
		t._location = location;

		return t;
	}

	static getOperator(string op)(Location location) {
		enum Type = DLexer.OperatorMap[op];

		Token t;
		t._type = Type;
		t._name = BuiltinName!op;
		t._location = location;

		return t;
	}
}

auto lex(Position base, Context context) {
	auto lexer = TokenRange();

	lexer.context = context;
	lexer.base = base;
	lexer.previous = base;
	lexer.content = base.getFullPosition(context).getSource().getContent();

	// Pop #!
	auto shebang = lexer.popSheBang();
	auto beginLocation = Location(base, base.getWithOffset(lexer.index));

	lexer.t = Token.getBegin(beginLocation, shebang);

	return lexer;
}

alias TokenRange = DLexer;

struct DLexer {
	enum BaseMap = () {
		auto ret = [
			// sdfmt off
			// Comments
			"//" : "?Comment",
			"/*" : "?Comment",
			"/+" : "?Comment",

			// Line directives.
			"#"  : "?PreprocessorDirective",

			// Integer literals.
			"0b" : "lexNumeric",
			"0B" : "lexNumeric",
			"0x" : "lexNumeric",
			"0X" : "lexNumeric",

			// String literals.
			"`"   : "lexString",
			`"`   : "lexString",
			"q{"  : "lexDString",
			`q"`  : "lexDString",
			`q"(` : "lexDString",
			`q"[` : "lexDString",
			`q"{` : "lexDString",
			`q"<` : "lexDString",
			`r"`  : "lexDString",

			// Character literals.
			"'" : "lexCharacter",
			// sdfmt on
		];

		return registerNumericPrefixes(ret);
	}();

	enum KeywordMap = getKeywordsMap();
	enum OperatorMap = getOperatorsMap();

	import source.lexbase;
	mixin LexBaseImpl!(Token, BaseMap, KeywordMap, OperatorMap);

	import source.name;
	Name popSheBang() {
		auto c = frontChar;
		if (c != '#') {
			return BuiltinName!"";
		}

		while (c != '\n') {
			popChar();
			c = frontChar;
		}

		return context.getName(content[0 .. index]);
	}

	/**
	 * Numbers.
	 */
	// sdfmt off
	import source.lexnumeric;
	mixin LexNumericImpl!(Token, [
		"" : "getIntegerLiteral",
		"u": "getIntegerLiteral",
		"U": "getIntegerLiteral",
		"ul": "getIntegerLiteral",
		"uL": "getIntegerLiteral",
		"Ul": "getIntegerLiteral",
		"UL": "getIntegerLiteral",
		"l": "getIntegerLiteral",
		"L": "getIntegerLiteral",
		"lu": "getIntegerLiteral",
		"lU": "getIntegerLiteral",
		"Lu": "getIntegerLiteral",
		"LU": "getIntegerLiteral",
		"f": "getIntegerFloatLiteral",
		"F": "getIntegerFloatLiteral",
	], [
		"" : "getDFloatLiteral",
		"f": "getDFloatLiteral",
		"F": "getDFloatLiteral",
		"L": "getDFloatLiteral",
		"l": "getDFloatLiteral",
	]);
	// sdfmt on

	auto getIntegerFloatLiteral(string s)(Location location, ulong value,
	                                      bool overflow) {
		if (overflow) {
			return getHexFloatLiteral(location, value, overflow, 0);
		}

		auto pf = Token.PackedFloat.fromInt(context, value);
		return Token.getFloatLiteral(location, pf);
	}

	auto getDFloatLiteral(string s, bool IsHex)(
		Location location,
		ulong mantissa,
		bool overflow,
		int exponent,
	) {
		if (s == "l") {
			return getError(location, "Use 'L' suffix instead of 'l'.");
		}

		return
			getFloatLiteral!("", IsHex)(location, mantissa, overflow, exponent);
	}

	/**
	 * Strings.
	 */
	// sdfmt off
	import source.lexstring;
	mixin LexStringImpl!(Token, [
		"" : "getStringLiteral",
		"c" : "getStringLiteral",
		"w" : "getStringLiteral",
		"d" : "getStringLiteral",
	]);
	// sdfmt on

	auto getStringLiteral(string s)(Location location, Name value) {
		return Token.getStringLiteral(location, value);
	}

	Token lexDString(string s : `r"`)() {
		uint l = s.length;
		return lexRawString!'"'(index - l);
	}

	Token lexDString(string s : "q{")() {
		uint begin = index - 2;
		uint start = index;

		auto lookahead = getLookahead();

		uint level = 1;
		while (level > 0) {
			lookahead.popFront();
			auto lt = lookahead.front;

			switch (lt.type) with (TokenType) {
				case Invalid:
					// Bubble up errors.
					index = lookahead.index;
					return lt;

				case End:
					index = lookahead.index - 1;
					return getExpectedError(begin, "`}` to end string literal");

				case OpenBrace:
					level++;
					break;

				case CloseBrace:
					level--;
					break;

				default:
					break;
			}
		}

		index = lookahead.index;
		return buildRawString(begin, start, index - 1);
	}

	private Token lexQDelimintedString(char Delimiter)() {
		static assert(Delimiter != '"', "Delimiter cannot be '\"'");

		uint begin = index - 3;
		uint start = index;

		// This is not technically correct, but the actual value of
		// previous doesn't matter when the delimiter isn't '"'.
		char previous = frontChar;
		char c = previous;

		while (c != '"' || previous != Delimiter) {
			if (reachedEOF()) {
				import std.format;
				enum E = format!"`%s\"` to end string literal"(Delimiter);
				return getExpectedError(begin, E);
			}

			popChar();
			previous = c;
			c = frontChar;
		}

		popChar();
		return buildRawString(begin, start, index - 2);
	}

	Token lexDString(string s : `q"(`)() {
		return lexQDelimintedString!')'();
	}

	Token lexDString(string s : `q"[`)() {
		return lexQDelimintedString!']'();
	}

	Token lexDString(string s : `q"{`)() {
		return lexQDelimintedString!'}'();
	}

	Token lexDString(string s : `q"<`)() {
		return lexQDelimintedString!'>'();
	}

	Token lexDString(string s : `q"`)() {
		uint idstart = index;
		uint begin = index - 2;

		Token t = lexIdentifier();
		if (t.type == TokenType.Invalid) {
			// If this is an error, pass it on!
			return t;
		}

		auto id = content[idstart .. index];

		if (!popLineBreak()) {
			return
				getError(begin, "Identifier must be followed by a line break.");
		}

		uint start = index;
		char c = frontChar;

		while (true) {
			if (reachedEOF()) {
				import std.format;
				auto expected = format!"`%s\"` to end string literal"(id);
				return getExpectedError(begin, expected);
			}

			for (size_t i = 0; i < id.length; i++) {
				if (c != id[i]) {
					goto NextLine;
				}

				popChar();
				c = frontChar;
			}

			if (c == '"') {
				break;
			}

		NextLine:
			popLine();
			c = frontChar;
			continue;
		}

		popChar();
		return buildRawString(begin, start, index - id.length - 1);
	}

	/**
	 * Preprocessor.
	 */
	import source.lexpreprocessor;
	mixin LexPreprocessorImpl!(Token, [TokenType.If: "processIfDirective"],
	                           ["line": "processLineDirective"]);

	Token processLineDirective(uint begin, Token i) {
		if (base.isMixin()) {
			// It is really unclear what this should actually do.
			// Disallow for now. DMD allows this.
			return getError(
				i.location,
				"#line directive are not allowed in string mixins."
			);
		}

		uint line;
		Name file;

		auto t = getNextPreprocessorToken();
		switch (t.type) with (TokenType) {
			case IntegerLiteral:
				auto l = t.packedInt.toInt(context);
				if (l <= uint.max) {
					line = cast(uint) l;
					break;
				}

				import std.format;
				return getError(
					t.location,
					format!"Expected 32-bits integers, not `%s`."(l)
				);

			case __Line__:
				line = t.location.getFullLocation(context).getStartLineNumber();
				break;

			case End:
				return getError(
					t.location,
					"A positive integer argument is expected after `#line`."
				);

			default:
				import std.format;
				return getError(
					t.location,
					format!"Expected a line number, not `%s`."(
						t.toString(context))
				);
		}

		t = getNextPreprocessorToken();
		switch (t.type) with (TokenType) {
			case StringLiteral:
				file = t.decodedString;
				break;

			case __File__:
				file = t.location.getFullLocation(context).getFileName();
				break;

			case End:
				goto End;

			default:
				import std.format;
				return getError(
					t.location,
					format!"Expected a file name as a string, not `%s`."(
						t.toString(context))
				);
		}

		t = getNextPreprocessorToken();
		if (t.type == TokenType.End) {
			goto End;
		}

		import std.format;
		return getError(
			t.location,
			format!"`%s` is not a valis line directive suffix."(
				t.toString(context))
		);

	End:
		context.registerLineDirective(t.location.stop, file, line);
		return getPreprocessorComment(begin, t);
	}

	Token processIfDirective(uint begin, Token i) {
		return getError(
			i.location,
			"C preprocessor directive `#if` is not supported, use `version` or `static if`."
		);
	}
}

auto getOperatorsMap() {
	// with(TokenType): currently isn't working https://issues.dlang.org/show_bug.cgi?id=14332
	with (TokenType) return [
		// sdfmt off
		"/"    : Slash,
		"/="   : SlashEqual,
		"."    : Dot,
		".."   : DotDot,
		"..."  : DotDotDot,
		"&"    : Ampersand,
		"&="   : AmpersandEqual,
		"&&"   : AmpersandAmpersand,
		"|"    : Pipe,
		"|="   : PipeEqual,
		"||"   : PipePipe,
		"-"    : Minus,
		"-="   : MinusEqual,
		"--"   : MinusMinus,
		"+"    : Plus,
		"+="   : PlusEqual,
		"++"   : PlusPlus,
		"<"    : SmallerThan,
		"<="   : SmallerEqual,
		"<<"   : LessLess,
		"<<="  : LessLessEqual,
		"<>"   : LessMore,
		"<>="  : LessMoreEqual,
		">"    : GreaterThan,
		">="   : GreaterEqual,
		">>="  : MoreMoreEqual,
		">>>=" : MoreMoreMoreEqual,
		">>"   : MoreMore,
		">>>"  : MoreMoreMore,
		"!"    : Bang,
		"!="   : BangEqual,
		"!<>"  : BangLessMore,
		"!<>=" : BangLessMoreEqual,
		"!<"   : BangLess,
		"!<="  : BangLessEqual,
		"!>"   : BangMore,
		"!>="  : BangMoreEqual,
		"("    : OpenParen,
		")"    : CloseParen,
		"["    : OpenBracket,
		"]"    : CloseBracket,
		"{"    : OpenBrace,
		"}"    : CloseBrace,
		"?"    : QuestionMark,
		","    : Comma,
		";"    : Semicolon,
		":"    : Colon,
		"$"    : Dollar,
		"="    : Equal,
		"=="   : EqualEqual,
		"*"    : Star,
		"*="   : StarEqual,
		"%"    : Percent,
		"%="   : PercentEqual,
		"^"    : Caret,
		"^="   : CaretEqual,
		"^^"   : CaretCaret,
		"^^="  : CaretCaretEqual,
		"~"    : Tilde,
		"~="   : TildeEqual,
		"@"    : At,
		"=>"   : FatArrow,
		"#"    : Hash,
		"\0"   : End,
		// sdfmt on
	];
}

auto getKeywordsMap() {
	// with(TokenType): currently isn't working https://issues.dlang.org/show_bug.cgi?id=14332
	with (TokenType) return [
		// sdfmt off
		"abstract"        : Abstract,
		"alias"           : Alias,
		"align"           : Align,
		"asm"             : Asm,
		"assert"          : Assert,
		"auto"            : Auto,
		"bool"            : Bool,
		"break"           : Break,
		"byte"            : Byte,
		"case"            : Case,
		"cast"            : Cast,
		"catch"           : Catch,
		"cent"            : Cent,
		"char"            : Char,
		"class"           : Class,
		"const"           : Const,
		"continue"        : Continue,
		"dchar"           : Dchar,
		"debug"           : Debug,
		"default"         : Default,
		"delegate"        : Delegate,
		"deprecated"      : Deprecated,
		"do"              : Do,
		"double"          : Double,
		"else"            : Else,
		"enum"            : Enum,
		"export"          : Export,
		"extern"          : Extern,
		"false"           : False,
		"final"           : Final,
		"finally"         : Finally,
		"float"           : Float,
		"for"             : For,
		"foreach"         : Foreach,
		"foreach_reverse" : ForeachReverse,
		"function"        : Function,
		"goto"            : Goto,
		"if"              : If,
		"immutable"       : Immutable,
		"import"          : Import,
		"in"              : In,
		"inout"           : Inout,
		"int"             : Int,
		"interface"       : Interface,
		"invariant"       : Invariant,
		"is"              : Is,
		"lazy"            : Lazy,
		"long"            : Long,
		"macro"           : Macro,
		"mixin"           : Mixin,
		"module"          : Module,
		"new"             : New,
		"nothrow"         : Nothrow,
		"null"            : Null,
		"out"             : Out,
		"override"        : Override,
		"package"         : Package,
		"pragma"          : Pragma,
		"private"         : Private,
		"protected"       : Protected,
		"public"          : Public,
		"pure"            : Pure,
		"real"            : Real,
		"ref"             : Ref,
		"return"          : Return,
		"scope"           : Scope,
		"shared"          : Shared,
		"short"           : Short,
		"static"          : Static,
		"struct"          : Struct,
		"super"           : Super,
		"switch"          : Switch,
		"synchronized"    : Synchronized,
		"template"        : Template,
		"this"            : This,
		"throw"           : Throw,
		"true"            : True,
		"try"             : Try,
		"typeid"          : Typeid,
		"typeof"          : Typeof,
		"ubyte"           : Ubyte,
		"ucent"           : Ucent,
		"uint"            : Uint,
		"ulong"           : Ulong,
		"union"           : Union,
		"unittest"        : Unittest,
		"ushort"          : Ushort,
		"version"         : Version,
		"void"            : Void,
		"wchar"           : Wchar,
		"while"           : While,
		"with"            : With,
		"__FILE__"        : __File__,
		"__LINE__"        : __Line__,
		"__gshared"       : __Gshared,
		"__traits"        : __Traits,
		"__vector"        : __Vector,
		"__parameters"    : __Parameters,
		// sdfmt on
	];
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
		auto lex = testlexer("a");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.Identifier);
		assert(t.name.toString(context) == "a");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("_");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.Identifier);
		assert(t.name.toString(context) == "_");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("_0");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.Identifier);
		assert(t.name.toString(context) == "_0");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0b0");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0b_0");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0b_0_");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0b_");
		lex.match(TokenType.Begin);
		lex.match(TokenType.Invalid);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0x0");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0x_0");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0x_0_");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0x_");
		lex.match(TokenType.Begin);
		lex.match(TokenType.Invalid);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("_0");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.Identifier);
		assert(t.name.toString(context) == "_0");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("é");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.Identifier);
		assert(t.name.toString(context) == "é");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("Γαῖα");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.Identifier);
		assert(t.name.toString(context) == "Γαῖα");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("🙈🙉🙊");
		lex.match(TokenType.Begin);
		lex.match(TokenType.Invalid);
		lex.match(TokenType.Invalid);
		lex.match(TokenType.Invalid);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1u");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1U");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1l");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1L");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1ul");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1uL");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1Ul");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1UL");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1lu");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1lU");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1Lu");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1LU");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1F");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1.f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		lex.match(TokenType.Dot);
		lex.match(TokenType.Identifier);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1.1f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1.1F");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1.1L");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		// /!\ l is *NOT*  a valid suffix, this one is case sensitive.
		auto lex = testlexer("1.1l");
		lex.match(TokenType.Begin);
		lex.match(TokenType.Invalid);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1.1F");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1. f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		lex.match(TokenType.Dot);
		lex.match(TokenType.Identifier);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("1.1 f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		lex.match(TokenType.Identifier);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0x1.921fb54442d1846ap+1L");
		lex.match(TokenType.Begin);
		/*
		lex.match(TokenType.FloatLiteral);
		/*/
		// FIXME: Decode floats with overflowing mantissa.
		lex.match(TokenType.Invalid);
		// */
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("0x1.a934f0979a3715fcp+1L");
		lex.match(TokenType.Begin);
		/*
		lex.match(TokenType.FloatLiteral);
		/*/
		// FIXME: Decode floats with overflowing mantissa.
		lex.match(TokenType.Invalid);
		// */
		assert(lex.front.type == TokenType.End);
	}

	// Overflow.
	{
		auto lex = testlexer("18446744073709551615f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("18446744073709551618f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.Invalid);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"(("))"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == `(")`);
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"[]"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"{<}"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "<");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"<">"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == `"`);
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("q{{foo}}");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "{foo}");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"EOF
EOF"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("q\"UNICODE_LINE_BREAK\u0085UNICODE_LINE_BREAK\"");
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"EOF

EOF"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "\n");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"MONKEYS
🙈🙉🙊
MONKEYS"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "🙈🙉🙊\n");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"I_LOVE_PYTHON
"""python comment!"""
I_LOVE_PYTHON"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(
			t.decodedString.toString(context) == `"""python comment!"""` ~ '\n'
		);
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"FOO
FOO
"`);
		lex.match(TokenType.Begin);
		lex.match(TokenType.Invalid);
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`r"\r"`);
		lex.match(TokenType.Begin);

		auto t = lex.front;

		assert(t.type == TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == "\\r");
		lex.popFront();

		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer("body");
		lex.match(TokenType.Begin);
		assert(lex.front.type == TokenType.Identifier);
	}
}
