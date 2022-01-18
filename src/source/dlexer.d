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
			// WhiteSpaces
			" "    : "-skip",
			"\t"   : "-skip",
			"\v"   : "-skip",
			"\f"   : "-skip",
			"\n"   : "-skip",
			"\r"   : "-skip",
			
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
			"`"  : "lexString",
			`"`  : "lexString",
			`x"` : "lexDString",
			`q"` : "lexDString",
			"q{" : "lexDString",
			`r"` : "lexDString",
			
			// Character literals.
			"'" : "lexString",
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
	
	Token lexDString(string s)() in {
		assert(index >= s.length);
	} do {
		assert(0, "Not implemented");
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
