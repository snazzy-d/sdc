/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.token;

import sdc.location;

/* I don't really have to tell you to keep this
 * table and the TokenType enum in sync, do I?
 */
immutable string[182] tokenToString = [
"none", "identifier", "string literal", "character literal",
"integer literal", "float literal", "abstract", "alias", "align",
"asm", "assert", "auto", "body", "bool", "break", "byte", "case",
"cast", "catch", "cdouble", "cent", "cfloat", "char", "class",
"const", "continue", "creal", "dchar", "debug", "default",
"delegate", "delete", "deprecated", "do", "double", "else", "enum",
"export", "extern", "false", "final", "finally", "float", "for",
"foreach", "foreach_reverse", "function", "goto", "idouble", "if",
"ifloat", "immutable", "import", "in", "inout", "int", "interface",
"invariant", "ireal", "is", "lazy", "long", "macro", "mixin", "module",
"new", "nothrow", "null", "out", "override", "package", "pragma",
"private", "protected", "public", "pure", "real", "ref", "return",
"scope", "shared", "short", "static", "struct", "super",
"switch", "synchronized", "template", "this", "throw", "true",
"try", "typedef", "typeid", "typeof", "ubyte", "ucent", "uint",
"ulong", "union", "unittest", "ushort", "version", "void", "volatile",
"wchar", "while", "with", "__FILE__", "__LINE__", "__gshared",
"__thread", "__traits", "@property", "@safe", "@trusted", "@system",
"@disable",
"/", "/=", ".", "..", "...", "&", "&=", "&&", "|", "|=", "||",
"-", "-=", "--", "+", "+=", "++", "<", "<=", "<<", "<<=", "<>", "<>=",
">", ">=", ">>=", ">>>=", ">>", ">>>", "!", "!=", "!<>", "!<>=", "!<",
"!<=", "!>", "!>=", "(", ")", "[", "]", "{", "}", "?", ",", ";",
":", "$", "=", "==", "*", "*=", "%", "%=", "^", "^=", "^^", "~", "~=",
"(>^(>O_O)>", "symbol", "number", "BEGIN", "EOF"
];

enum TokenType
{
    None = 0,
    
    // Literals
    Identifier,
    StringLiteral,
    CharacterLiteral,
    IntegerLiteral,
    FloatLiteral,
    
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
    __File__, __Line__, __Gshared, __Thread, __Traits,
    atProperty, atSafe, atTrusted, atSystem, atDisable,
    
    /// Symbols.
    Slash,             // /
    SlashAssign,       // /=
    Dot,               // .
    DoubleDot,         // ..
    TripleDot,         // ...
    Ampersand,         // &
    AmpersandAssign,   // &=
    DoubleAmpersand,   // &&
    Pipe,              // |
    PipeAssign,        // |=
    DoublePipe,        // ||
    Dash,              // -
    DashAssign,        // -=
    DoubleDash,        // --
    Plus,              // +
    PlusAssign,        // +=
    DoublePlus,        // ++
    Less,              // <
    LessAssign,        // <=
    DoubleLess,        // <<
    DoubleLessAssign,  // <<=
    LessGreater,       // <>
    LessGreaterAssign, // <>= 
    Greater,           // >
    GreaterAssign,     // >=
    DoubleGreaterAssign, // >>=
    TripleGreaterAssign, // >>>=
    DoubleGreater,       // >>
    TripleGreater,       // >>>
    Bang,                // !
    BangAssign,          // !=
    BangLessGreater,     // !<>
    BangLessGreaterAssign,  // !<>=
    BangLess,               // !<
    BangLessAssign,         // !<=
    BangGreater,            // !>
    BangGreaterAssign,      // !>=
    OpenParen,              // (
    CloseParen,             // )
    OpenBracket,            // [
    CloseBracket,           // ]
    OpenBrace,              // {
    CloseBrace,             // }
    QuestionMark,           // ?
    Comma,                  // ,
    Semicolon,              // ;
    Colon,                  // :
    Dollar,                 // $
    Assign,                 // =
    DoubleAssign,           // ==
    Asterix,                // *
    AsterixAssign,          // *=
    Percent,                // %
    PercentAssign,          // %=
    Caret,                  // ^
    CaretAssign,            // ^=
    DoubleCaret,            // ^^
    Tilde,                  // ~
    TildeAssign,            // ~=
    
    opKirbyRape,            // (>^(>O_O)>
    Symbol,
    Number,
    
    Begin,
    End,
}


__gshared TokenType[string] keywordToTokenType;


TokenType identifierType(string ident)
{
    synchronized {
        if (ident in keywordToTokenType) {
            return keywordToTokenType[ident];
        } else {
            return TokenType.Identifier;
        }
    }
}

static this()
{
    with (TokenType) {
        keywordToTokenType["abstract"] = Abstract;
        keywordToTokenType["alias"] = Alias;
        keywordToTokenType["align"] = Align;
        keywordToTokenType["asm"] = Asm;
        keywordToTokenType["assert"] = Assert;
        keywordToTokenType["auto"] = Auto;
        keywordToTokenType["body"] = Body;
        keywordToTokenType["bool"] = Bool;
        keywordToTokenType["break"] = Break;
        keywordToTokenType["byte"] = Byte;
        keywordToTokenType["case"] = Case;
        keywordToTokenType["cast"] = Cast;
        keywordToTokenType["catch"] = Catch;
        keywordToTokenType["cdouble"] = Cdouble;
        keywordToTokenType["cent"] = Cent;
        keywordToTokenType["cfloat"] = Cfloat;
        keywordToTokenType["char"] = Char;
        keywordToTokenType["class"] = Class;
        keywordToTokenType["const"] = Const;
        keywordToTokenType["continue"] = Continue;
        keywordToTokenType["creal"] = Creal;
        keywordToTokenType["dchar"] = Dchar;
        keywordToTokenType["debug"] = Debug;
        keywordToTokenType["default"] = Default;
        keywordToTokenType["delegate"] = Delegate;
        keywordToTokenType["delete"] = Delete;
        keywordToTokenType["deprecated"] = Deprecated;
        keywordToTokenType["do"] = Do;
        keywordToTokenType["double"] = Double;
        keywordToTokenType["else"] = Else;
        keywordToTokenType["enum"] = Enum;
        keywordToTokenType["export"] = Export;
        keywordToTokenType["extern"] = Extern;
        keywordToTokenType["false"] = False;
        keywordToTokenType["final"] = Final;
        keywordToTokenType["finally"] = Finally;
        keywordToTokenType["float"] = Float;
        keywordToTokenType["for"] = For;
        keywordToTokenType["foreach"] = Foreach;
        keywordToTokenType["foreach_reverse"] = ForeachReverse;
        keywordToTokenType["function"] = Function;
        keywordToTokenType["goto"] = Goto;
        keywordToTokenType["idouble"] = Idouble;
        keywordToTokenType["ifloat"] = Ifloat;
        keywordToTokenType["immutable"] = Immutable;
        keywordToTokenType["import"] = Import;
        keywordToTokenType["in"] = In;
        keywordToTokenType["inout"] = Inout;
        keywordToTokenType["int"] = Int;
        keywordToTokenType["interface"] = Interface;
        keywordToTokenType["invariant"] = Invariant;
        keywordToTokenType["ireal"] = Ireal;
        keywordToTokenType["is"] = Is;
        keywordToTokenType["lazy"] = Lazy;
        keywordToTokenType["long"] = Long;
        keywordToTokenType["macro"] = Macro;
        keywordToTokenType["mixin"] = Mixin;
        keywordToTokenType["module"] = Module;
        keywordToTokenType["new"] = New;
        keywordToTokenType["nothrow"] = Nothrow;
        keywordToTokenType["null"] = Null;
        keywordToTokenType["out"] = Out;
        keywordToTokenType["override"] = Override;
        keywordToTokenType["package"] = Package;
        keywordToTokenType["pragma"] = Pragma;
        keywordToTokenType["private"] = Private;
        keywordToTokenType["protected"] = Protected;
        keywordToTokenType["public"] = Public;
        keywordToTokenType["pure"] = Pure;
        keywordToTokenType["real"] = Real;
        keywordToTokenType["ref"] = Ref;
        keywordToTokenType["return"] = Return;
        keywordToTokenType["scope"] = Scope;
        keywordToTokenType["shared"] = Shared;
        keywordToTokenType["short"] = Short;
        keywordToTokenType["static"] = Static;
        keywordToTokenType["struct"] = Struct;
        keywordToTokenType["super"] = Super;
        keywordToTokenType["switch"] = Switch;
        keywordToTokenType["synchronized"] = Synchronized;
        keywordToTokenType["template"] = Template;
        keywordToTokenType["this"] = This;
        keywordToTokenType["throw"] = Throw;
        keywordToTokenType["true"] = True;
        keywordToTokenType["try"] = Try;
        keywordToTokenType["typedef"] = Typedef;
        keywordToTokenType["typeid"] = Typeid;
        keywordToTokenType["typeof"] = Typeof;
        keywordToTokenType["ubyte"] = Ubyte;
        keywordToTokenType["ucent"] = Ucent;
        keywordToTokenType["uint"] = Uint;
        keywordToTokenType["ulong"] = Ulong;
        keywordToTokenType["union"] = Union;
        keywordToTokenType["unittest"] = Unittest;
        keywordToTokenType["ushort"] = Ushort;
        keywordToTokenType["version"] = Version;
        keywordToTokenType["void"] = Void;
        keywordToTokenType["volatile"] = Volatile;
        keywordToTokenType["wchar"] = Wchar;
        keywordToTokenType["while"] = While;
        keywordToTokenType["with"] = With;
        keywordToTokenType["__FILE__"] = __File__;
        keywordToTokenType["__LINE__"] = __Line__;
        keywordToTokenType["__gshared"] = __Gshared;
        keywordToTokenType["__thread"] = __Thread;
        keywordToTokenType["__traits"] = __Traits;
        keywordToTokenType["@property"] = atProperty;
        keywordToTokenType["@safe"] = atSafe;
        keywordToTokenType["@trusted"] = atTrusted;
        keywordToTokenType["@system"] = atSystem;
        keywordToTokenType["@disable"] = atDisable;
    }
}


class Token
{
    TokenType type;
    string value;
    Location location;
}
