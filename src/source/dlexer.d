module source.dlexer;

import source.context;
import source.location;

enum TokenType {
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
	Body, Bool, Break, Byte,
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
	Less,               // <
	LessEqual,          // <=
	LessLess,           // <<
	LessLessEqual,      // <<=
	LessMore,           // <>
	LessMoreEqual,      // <>=
	More,               // >
	MoreEqual,          // >=
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
	EqualMore,          // =>
	Hash,               // #
}

struct Token {
	import source.location;
	Location location;
	
	TokenType type;
	
	import source.name;
	Name name;
	
	import source.context;
	string toString(Context context) {
		return (type >= TokenType.Identifier)
			? name.toString(context)
			: location.getFullLocation(context).getSlice();
	}
}

auto lex(Position base, Context context) {
	auto lexer = TokenRange();
	
	lexer.content = base.getFullPosition(context).getSource().getContent();
	lexer.t.type = TokenType.Begin;
	
	lexer.context = context;
	lexer.base = base;
	lexer.previous = base;
	
	// Pop #!
	lexer.popSheBang();
	
	lexer.t.location =  Location(base, base.getWithOffset(lexer.index));
	return lexer;
}

alias TokenRange = DLexer;

struct DLexer {
	enum BaseMap = () {
		auto ret = [
			// Comments
			"//" : "?tokenizeComments:lexComment|popComment",
			"/*" : "?tokenizeComments:lexComment|popComment",
			"/+" : "?tokenizeComments:lexComment|popComment",
			
			// Integer literals.
			"0b" : "lexNumeric",
			"0B" : "lexNumeric",
			"0x" : "lexNumeric",
			"0X" : "lexNumeric",
			
			// String literals.
			"`"   : "lexDString",
			`"`   : "lexDString",
			"q{"  : "lexDString",
			`q"`  : "lexDString",
			`q"(` : "lexDString",
			`q"[` : "lexDString",
			`q"{` : "lexDString",
			`q"<` : "lexDString",
			`r"`  : "lexDString",
			
			// Character literals.
			"'" : "lexCharacter",
		];
		
		foreach (i; 0 .. 10) {
			import std.conv;
			ret[to!string(i)] = "lexNumeric";
		}
		
		return ret;
	}();
	
	import source.lexerutil;
	mixin TokenRangeImpl!(Token, BaseMap, getKeywordsMap(), getOperatorsMap());
	
	void popSheBang() {
		auto c = frontChar;
		if (c == '#') {
			while (c != '\n') {
				popChar();
				c = frontChar;
			}
		}
	}
	
	import source.lexnumeric;
	mixin LexNumericImpl!(Token, [
		"" : TokenType.IntegerLiteral,
		"u": TokenType.IntegerLiteral,
		"U": TokenType.IntegerLiteral,
		"ul": TokenType.IntegerLiteral,
		"uL": TokenType.IntegerLiteral,
		"Ul": TokenType.IntegerLiteral,
		"UL": TokenType.IntegerLiteral,
		"l": TokenType.IntegerLiteral,
		"L": TokenType.IntegerLiteral,
		"lu": TokenType.IntegerLiteral,
		"lU": TokenType.IntegerLiteral,
		"Lu": TokenType.IntegerLiteral,
		"LU": TokenType.IntegerLiteral,
		"f": TokenType.FloatLiteral,
		"F": TokenType.FloatLiteral,
	], [
		"" : TokenType.FloatLiteral,
		"f": TokenType.FloatLiteral,
		"F": TokenType.FloatLiteral,
		"L": TokenType.FloatLiteral,
	], null, [
		"l": "lexFloatSuffixError",
	]);
	
	auto lexFloatSuffixError(string s : "l")(uint begin, uint prefixStart) {
		Token t;
		t.location = base.getWithOffsets(begin, index);
		setError(t, "Use 'L' suffix instead of 'l'");
		return t;
	}
	
	Token lexStringPostfix(Token t) {
		if (t.type == TokenType.Invalid) {
			// Forward errors.
			return t;
		}
		
		char c = frontChar;
		if (c != 'c' && c != 'w' && c !='d') {
			// No postfix, all good.
			return t;
		}
		
		popChar();

		t.location = Location(t.location.start, base.getWithOffset(index));
		return t;
	}
	
	Token lexDString(string s : `"`)() {
		return lexStringPostfix(lexString!s());
	}
	
	Token lexDString(string s : "`")() {
		return lexStringPostfix(lexString!s());
	}
	
	Token lexDString(string s : `r"`)() {
		immutable begin = cast(uint) (index - s.length);
		return lexStringPostfix(lexRawString!'"'(begin));
	}
	
	Token lexStringPostfix(uint begin, size_t start, size_t stop) {
		char c = frontChar;
		if (c == 'c' && c == 'w' && c =='d') {
			popChar();
		}
		
		Token t;
		t.type = TokenType.StringLiteral;
		t.location = base.getWithOffsets(begin, index);

		if (decodeStrings) {
			t.name = context.getName(content[start .. stop]);
		}

		return t;
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
				
				case End: {
					Token t;
					setError(t, "Unexpected end of file.");
					index = lookahead.index - 1;
					t.location = base.getWithOffsets(begin, index);
					return t;
				}
				
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
		return lexStringPostfix(begin, start, index - 1);
	}

	Token lexQDelimintedString(char delimiter) in {
		assert(delimiter != '"');
	} do {
		uint begin = index - 3;
		uint start = index;

		// This is not technically correct, but the actual value of
		// previous doesn't matter when the delimiter isn't '"'.
		char previous = frontChar;
		char c = previous;

		while (c != '\0' && (c != '"' || previous != delimiter)) {
			popChar();
			previous = c;
			c = frontChar;
		}

		if (c == '\0') {
			Token t;
			setError(t, "Unexpected end of file");
			t.location = base.getWithOffsets(begin, index);
			return t;
		}

		popChar();
		return lexStringPostfix(begin, start, index - 2);
	}

	Token lexDString(string s : `q"(`)() {
		return lexQDelimintedString(')');
	}

	Token lexDString(string s : `q"[`)() {
		return lexQDelimintedString(']');
	}

	Token lexDString(string s : `q"{`)() {
		return lexQDelimintedString('}');
	}

	Token lexDString(string s : `q"<`)() {
		return lexQDelimintedString('>');
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

		if (frontChar == '\r') {
			// Be nice to the Windows minions out there.
			popChar();
		}

		if (frontChar != '\n') {
			setError(t, "Identifier must be followed by a new line.");
			t.location = base.getWithOffsets(begin, index);
			return t;
		}

		popChar();

		uint start = index;
		char c = frontChar;

		// Skip the inital chars where a match is not possible.
		for (size_t i = 0; c != '\0' && i < id.length; i++) {
			popChar();
			c = frontChar;
		}

		while (true) {
			while (c != '\0' && c != '"')  {
				popChar();
				c = frontChar;
			}

			if (c == '\0') {
				setError(t, "Unexpected end of file");
				t.location = base.getWithOffsets(begin, index);
				return t;
			}

			scope(success) {
				popChar();
			}

			if (content[index - id.length - 1] != '\n') {
				continue;
			}

			for (size_t i = 0; c != '\0' && i < id.length; i++) {
				if (content[index - id.length + i] != id[i]) {
					continue;
				}
			}

			// We found our guy.
			break;
		}

		return lexStringPostfix(begin, start, index - id.length - 1);
	}
}

auto getOperatorsMap() {
	//with(TokenType): currently isn't working https://issues.dlang.org/show_bug.cgi?id=14332
	with(TokenType)
	return [
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
		"<"    : Less,
		"<="   : LessEqual,
		"<<"   : LessLess,
		"<<="  : LessLessEqual,
		"<>"   : LessMore,
		"<>="  : LessMoreEqual,
		">"    : More,
		">="   : MoreEqual,
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
		"=>"   : EqualMore,
		"#"    : Hash,
		"\0"   : End,
	];
}

auto getKeywordsMap() {
	//with(TokenType): currently isn't working https://issues.dlang.org/show_bug.cgi?id=14332
	with(TokenType)
	return [
		"abstract"        : Abstract,
		"alias"           : Alias,
		"align"           : Align,
		"asm"             : Asm,
		"assert"          : Assert,
		"auto"            : Auto,
		"body"            : Body,
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
		"volatile"        : Volatile,
		"wchar"           : Wchar,
		"while"           : While,
		"with"            : With,
		"__FILE__"        : __File__,
		"__LINE__"        : __Line__,
		"__gshared"       : __Gshared,
		"__traits"        : __Traits,
		"__vector"        : __Vector,
		"__parameters"    : __Parameters,
	];
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
		auto lex = testlexer("0");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer("1");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer("1.");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer("1.0");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer("1. 0");
		lex.match(TokenType.Begin);
		lex.match(TokenType.FloatLiteral);
		lex.match(TokenType.IntegerLiteral);
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer("1..");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		lex.match(TokenType.DotDot);
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer("1 .");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		lex.match(TokenType.Dot);
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
		auto lex = testlexer(`q"(("))"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == `(")`);
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"[]"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == "");
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}

	{
		auto lex = testlexer(`q"{<}"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == "<");
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer(`q"<">"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == `"`);
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer("q{{foo}}");
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == "{foo}");
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer(`q"EOF
EOF"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == "");
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer(`q"EOF

EOF"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == "\n");
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
		assert(t.name.toString(context) == "🙈🙉🙊\n");
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
		assert(t.name.toString(context) == `"""python comment!"""` ~ '\n');
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}
	
	{
		auto lex = testlexer(`r"\r"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == "\\r");
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}
}