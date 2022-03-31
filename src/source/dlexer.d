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
	
	Token lexDString(string s : `r"`)() {
		immutable begin = cast(uint) (index - s.length);
		return lexRawString!'"'(begin);
	}
	
	Token lexDString(string s : "q{")() {
		uint begin = index - 2;
		uint start = index;
		
		Token t;
		t.type = TokenType.StringLiteral;
		
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
					setError(t, "Unexpected end of file.");
					index = lookahead.index - 1;
					t.location = base.getWithOffsets(begin, index);
					return t;
				
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
		
		if (decodeStrings) {
			uint end = lookahead.index - 1;
			t.name = context.getName(content[start .. end]);
		}
		
		index = lookahead.index;
		t.location = base.getWithOffsets(begin, index);
		return t;
	}

	Token lexQDelimintedString(char delimiter) in {
		assert(delimiter != '"');
	} do {
		uint begin = index - 3;
		uint start = index;

		Token t;
		t.type = TokenType.StringLiteral;

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
			setError(t, "Unexpected end of file");
			t.location = base.getWithOffsets(begin, index);
			return t;
		}

		if (decodeStrings) {
			string decoded = content[start .. index - 1];
			t.name = context.getName(decoded);
		}

		popChar();

		t.location = base.getWithOffsets(begin, index);
		return t;
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

	Token lexDString(string s)() in {
		assert(index >= s.length);
	} do {
		assert(0, s ~ " style string are not implemented");
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
		auto lex = testlexer("1f");
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
		auto lex = testlexer("1. f");
		lex.match(TokenType.Begin);
		lex.match(TokenType.IntegerLiteral);
		lex.match(TokenType.Dot);
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
		auto lex = testlexer(`r"\r"`);
		lex.match(TokenType.Begin);
		
		auto t = lex.front;
		
		assert(t.type == TokenType.StringLiteral);
		assert(t.name.toString(context) == "\\r");
		lex.popFront();
		
		assert(lex.front.type == TokenType.End);
	}
}