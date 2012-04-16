/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.token;

import sdc.location;


immutable string[179] tokenToString = [
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
"__thread", "__traits",
"/", "/=", ".", "..", "...", "&", "&=", "&&", "|", "|=", "||",
"-", "-=", "--", "+", "+=", "++", "<", "<=", "<<", "<<=", "<>", "<>=",
">", ">=", ">>=", ">>>=", ">>", ">>>", "!", "!=", "!<>", "!<>=", "!<",
"!<=", "!>", "!>=", "(", ")", "[", "]", "{", "}", "?", ",", ";",
":", "$", "=", "==", "*", "*=", "%", "%=", "^", "^=", "^^", "^^=", "~", "~=",
"@",
"(>^(>O_O)>", "symbol", "number", "BEGIN", "EOF"
];

/**
 * Ensure that the above list and following enum stay in sync,
 * and that the enum starts at zero and increases sequentially 
 * (i.e. adding a member increases TokenType.max).
 */
static assert(TokenType.min == 0);
static assert(tokenToString.length == TokenType.max + 1, "the tokenToString array and TokenType enum are out of sync.");
static assert(TokenType.max + 1 == __traits(allMembers, TokenType).length, "all TokenType enum members must be sequential.");

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
    
    /// Symbols.
    Slash,                  // /
    SlashAssign,            // /=
    Dot,                    // .
    DoubleDot,              // ..
    TripleDot,              // ...
    Ampersand,              // &
    AmpersandAssign,        // &=
    DoubleAmpersand,        // &&
    Pipe,                   // |
    PipeAssign,             // |=
    DoublePipe,             // ||
    Dash,                   // -
    DashAssign,             // -=
    DoubleDash,             // --
    Plus,                   // +
    PlusAssign,             // +=
    DoublePlus,             // ++
    Less,                   // <
    LessAssign,             // <=
    DoubleLess,             // <<
    DoubleLessAssign,       // <<=
    LessGreater,            // <>
    LessGreaterAssign,      // <>= 
    Greater,                // >
    GreaterAssign,          // >=
    DoubleGreaterAssign,    // >>=
    TripleGreaterAssign,    // >>>=
    DoubleGreater,          // >>
    TripleGreater,          // >>>
    Bang,                   // !
    BangAssign,             // !=
    BangLessGreater,        // !<>
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
    DoubleCaretAssign,      // ^^=
    Tilde,                  // ~
    TildeAssign,            // ~=
    At,                     // @
    
    opKirbyRape,            // (>^(>O_O)>
    Symbol,
    Number,
    
    Begin,
    End,
}


/**
 * Holds the type, the actual string and location within the source file.
 */
class Token
{
    TokenType type;
    string value;
    Location location;
    
    override string toString()
    {
        return tokenToString[type];
    }
}


/**
 * Go from a string identifier to a TokenType.
 *
 * Side-effects:
 *   None.
 *
 * Returns:
 *   Always a TokenType, for unknown ones TokenType.Identifier.
 */
TokenType identifierType(string ident)
{
    switch(ident) {
    case "abstract":        return TokenType.Abstract;
    case "alias":           return TokenType.Alias;
    case "align":           return TokenType.Align;
    case "asm":             return TokenType.Asm;
    case "assert":          return TokenType.Assert;
    case "auto":            return TokenType.Auto;
    case "body":            return TokenType.Body;
    case "bool":            return TokenType.Bool;
    case "break":           return TokenType.Break;
    case "byte":            return TokenType.Byte;
    case "case":            return TokenType.Case;
    case "cast":            return TokenType.Cast;
    case "catch":           return TokenType.Catch;
    case "cdouble":         return TokenType.Cdouble;
    case "cent":            return TokenType.Cent;
    case "cfloat":          return TokenType.Cfloat;
    case "char":            return TokenType.Char;
    case "class":           return TokenType.Class;
    case "const":           return TokenType.Const;
    case "continue":        return TokenType.Continue;
    case "creal":           return TokenType.Creal;
    case "dchar":           return TokenType.Dchar;
    case "debug":           return TokenType.Debug;
    case "default":         return TokenType.Default;
    case "delegate":        return TokenType.Delegate;
    case "delete":          return TokenType.Delete;
    case "deprecated":      return TokenType.Deprecated;
    case "do":              return TokenType.Do;
    case "double":          return TokenType.Double;
    case "else":            return TokenType.Else;
    case "enum":            return TokenType.Enum;
    case "export":          return TokenType.Export;
    case "extern":          return TokenType.Extern;
    case "false":           return TokenType.False;
    case "final":           return TokenType.Final;
    case "finally":         return TokenType.Finally;
    case "float":           return TokenType.Float;
    case "for":             return TokenType.For;
    case "foreach":         return TokenType.Foreach;
    case "foreach_reverse": return TokenType.ForeachReverse;
    case "function":        return TokenType.Function;
    case "goto":            return TokenType.Goto;
    case "idouble":         return TokenType.Idouble;
    case "if":              return TokenType.If;
    case "ifloat":          return TokenType.Ifloat;
    case "immutable":       return TokenType.Immutable;
    case "import":          return TokenType.Import;
    case "in":              return TokenType.In;
    case "inout":           return TokenType.Inout;
    case "int":             return TokenType.Int;
    case "interface":       return TokenType.Interface;
    case "invariant":       return TokenType.Invariant;
    case "ireal":           return TokenType.Ireal;
    case "is":              return TokenType.Is;
    case "lazy":            return TokenType.Lazy;
    case "long":            return TokenType.Long;
    case "macro":           return TokenType.Macro;
    case "mixin":           return TokenType.Mixin;
    case "module":          return TokenType.Module;
    case "new":             return TokenType.New;
    case "nothrow":         return TokenType.Nothrow;
    case "null":            return TokenType.Null;
    case "out":             return TokenType.Out;
    case "override":        return TokenType.Override;
    case "package":         return TokenType.Package;
    case "pragma":          return TokenType.Pragma;
    case "private":         return TokenType.Private;
    case "protected":       return TokenType.Protected;
    case "public":          return TokenType.Public;
    case "pure":            return TokenType.Pure;
    case "real":            return TokenType.Real;
    case "ref":             return TokenType.Ref;
    case "return":          return TokenType.Return;
    case "scope":           return TokenType.Scope;
    case "shared":          return TokenType.Shared;
    case "short":           return TokenType.Short;
    case "static":          return TokenType.Static;
    case "struct":          return TokenType.Struct;
    case "super":           return TokenType.Super;
    case "switch":          return TokenType.Switch;
    case "synchronized":    return TokenType.Synchronized;
    case "template":        return TokenType.Template;
    case "this":            return TokenType.This;
    case "throw":           return TokenType.Throw;
    case "true":            return TokenType.True;
    case "try":             return TokenType.Try;
    case "typedef":         return TokenType.Typedef;
    case "typeid":          return TokenType.Typeid;
    case "typeof":          return TokenType.Typeof;
    case "ubyte":           return TokenType.Ubyte;
    case "ucent":           return TokenType.Ucent;
    case "uint":            return TokenType.Uint;
    case "ulong":           return TokenType.Ulong;
    case "union":           return TokenType.Union;
    case "unittest":        return TokenType.Unittest;
    case "ushort":          return TokenType.Ushort;
    case "version":         return TokenType.Version;
    case "void":            return TokenType.Void;
    case "volatile":        return TokenType.Volatile;
    case "wchar":           return TokenType.Wchar;
    case "while":           return TokenType.While;
    case "with":            return TokenType.With;
    case "__FILE__":        return TokenType.__File__;
    case "__LINE__":        return TokenType.__Line__;
    case "__gshared":       return TokenType.__Gshared;
    case "__thread":        return TokenType.__Thread;
    case "__traits":        return TokenType.__Traits;
    default:                return TokenType.Identifier;
    }
}
