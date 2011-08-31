/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.iasm;

import std.string;

import sdc.compilererror;
import sdc.location;
import sdc.token;
import sdc.tokenstream;
import sdc.util;
import sdc.parser.base;
import sdc.ast.base;


immutable DIRECTIVES = [
"align", "even", "naked",
"db", "ds", "di", "dl", "df", "dd", "de"
];

immutable X86_REGISTERS = [
"AL", "AH", "AX", "EAX",
"BL", "BH", "BX", "EBX",
"CL", "CH", "CX", "ECX",
"DL", "DH", "DX", "EDX",
"BP", "EBP",
"SP", "ESP",
"DI", "EDI",
"SI", "ESI",
"ES", "CS", "SS", "DS", "GS", "FS"
"CR0", "CR2", "CR3", "CR4",
"DR0", "DR1", "DR2", "DR3", "DR6", "DR7",
"TR3", "TR4", "TR5", "TR6", "TR7",
"ST", "ST(0)", "ST(1)", "ST(2)", "ST(3)",
"ST(4)", "ST(5)", "ST(6)", "ST(7)",
"MM0", "MM1", "MM2", "MM3", "MM4", "MM5", "MM6", "MM7",
"XMM0", "XMM1", "XMM2", "XMM3", "XMM4", "XMM5", "XMM6", "XMM7"
];

enum AsmInstructionType
{
    Label,
    Directive,
    Opcode
} 

class AsmInstruction
{
    Location location;
    AsmInstructionType type;
    string label;   // Optional.
    Opcode opcode;  // Optional.
    Directive directive;  // Optional.
}

enum SizePrefix
{
    None,
    Near,
    Far,
    Byte,
    Short,
    Int,
    Word,
    DWord,
    QWord,
    Float,
    Double,
    Real
}

class Opcode
{
    Location location;
    bool label = false;
    string instruction;
}

enum OperandType
{
    Register,
}

class Operand
{
    Location location;
}

class AsmExpNode
{
    Location location;
}

class AsmExp : AsmExpNode
{
    AsmLogOrExp logOrExp;
    AsmExp lhs;  // Optional.
    AsmExp rhs;  // Optional.
}

class AsmLogOrExp : AsmExpNode
{
    AsmLogAndExp lhs;
    AsmLogAndExp rhs;  // Optional.
}

class AsmLogAndExp : AsmExpNode
{
    AsmOrExp lhs;
    AsmOrExp rhs;  // Optional.
}

class AsmOrExp : AsmExpNode
{
    AsmXorExp lhs;
    AsmXorExp rhs;  // Optional.
}

class AsmXorExp : AsmExpNode
{
    AsmAndExp lhs;
    AsmAndExp rhs;  // Optional.
}

class AsmAndExp : AsmExpNode
{
    AsmEqualExp lhs;
    AsmEqualExp rhs;  // Optional.
}

class AsmEqualExp : AsmExpNode
{
    bool equal;
    AsmRelExp lhs;
    AsmRelExp rhs;  // Optional.
}

enum RelType
{
    None,
    LT,
    LTE,
    GT,
    GTE,
}

class AsmRelExp : AsmExpNode
{
    RelType type;
    AsmShiftExp lhs;
    AsmShiftExp rhs;  // Optional.
}

enum ShiftType
{
    None,
    DoubleLeft,
    DoubleRight,
    TripleRight,
}

class AsmShiftExp : AsmExpNode
{
    ShiftType type;
    AsmAddExp lhs;
    AsmAddExp rhs;  // Optional.
}

class AsmAddExp : AsmExpNode
{
    bool addition;
    AsmMulExp lhs;
    AsmMulExp rhs;  // Optional.
}

enum MulType
{
    None,
    Multiply,
    Divide,
    Modulus,
}

class AsmMulExp : AsmExpNode
{
    MulType type;
    AsmBrExp lhs;
    AsmBrExp rhs;  // Optional.
}

class AsmBrExp : AsmExpNode
{
    AsmUnaExp unaExp;
    AsmExp exp;  // Optional.
}

enum UnaType
{
    Type,
    Offset,
    Seg,
    Plus,
    Minus,
    LogicalNot,
    BitwiseNot,
    PrimaryExp,
}

class AsmUnaExp : AsmExpNode
{
    UnaType type;
    SizePrefix prefix;  // Optional.
    AsmExp exp;  // Optional.
    AsmUnaExp unaExp;  // Optional.
    AsmPrimaryExp primaryExp;  // Optional.
}

enum PrimaryType
{
    IntegerLiteral,
    FloatLiteral,
    __LOCAL_SIZE,
    Dollar,
    Register,
    DotIdentifier,
}

class AsmPrimaryExp : AsmExpNode
{
    PrimaryType type;
    // All of these are optional, depending on the value of type.
    IntegerLiteral integerLiteral;
    FloatLiteral floatLiteral;
    string register;
    Identifier name;
    QualifiedName qualifiedName;
}

enum DirectiveType
{
    Align,
    Even,
    Naked,
    Db, Ds, Di, Dl, Df, Dd, De
}

class Directive
{
    Location location;
    DirectiveType type;
    Operand[] operands;
    IntegerExpression integerExpression;  // Optional.
}

class IntegerExpression
{
    Location location;
}


AsmInstruction[] parseAsm(string filename, Token[] tokens)
{
    auto end = new Token();
    end.type = TokenType.End;
    auto tstream = new TokenStream(filename, tokens ~ end);
    AsmInstruction[] program;
    
    while (tstream.peek.type != TokenType.End) {
        program ~= parseAsmInstruction(tstream);
        match(tstream, TokenType.Semicolon);
    }
    
    return program;
}

AsmInstruction parseAsmInstruction(TokenStream tstream)
{
    auto instruction = new AsmInstruction();
    auto startLocation = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Identifier && tstream.lookahead(1).type == TokenType.Colon) {
        auto ident = match(tstream, TokenType.Identifier);
        instruction.label = ident.value;
    } else if (tstream.peek.type == TokenType.Identifier && DIRECTIVES.contains(tstream.peek.value)) {
        instruction.directive = parseDirective(tstream);
    } else {
        instruction.opcode = parseOpcode(tstream);
    }
    
    auto endLocation = tstream.peek.location;
    instruction.location = endLocation - startLocation;
    return instruction;
}

Directive parseDirective(TokenStream tstream)
{
    auto directive = new Directive();
    directive.location = tstream.peek.location;
    auto ident = match(tstream, TokenType.Identifier);
    switch (ident.value) {
    case "naked":
        directive.type = DirectiveType.Naked;
        break;
    case "even":
        directive.type = DirectiveType.Even;
        break;
    default:
        throw new CompilerError(tstream.peek.location, "expected assembler directive.");
    }
    return directive;
}

Opcode parseOpcode(TokenStream tstream)
{
    auto opcode = new Opcode();
    if (tstream.peek.type != TokenType.Identifier) {
        throw new CompilerError(tstream.peek.location, format("expected instruction, not '%s'.", tstream.peek.value));
    }
    opcode.instruction = tstream.peek.value;
    tstream.get();
    return opcode;
}

AsmExp parseAsmExp(TokenStream tstream)
{
    auto exp = new AsmExp();
    exp.location = tstream.peek.location;
    exp.logOrExp = parseAsmLogOrExp(tstream);
    if (tstream.peek.type == TokenType.QuestionMark) {
        tstream.get();
        exp.lhs = parseAsmExp(tstream);
        match(tstream, TokenType.Colon);
        exp.rhs = parseAsmExp(tstream);
    }
    return exp;    
}

T parseSimpleBinaryExp(T, TokenType OP, string parent)(TokenStream tstream)
{
    auto exp = new T();
    exp.location = tstream.peek.location;
    mixin("exp.lhs = " ~ parent ~ "(tstream);");
    if (tstream.peek.type == OP) {
        tstream.get();
        mixin("exp.rhs = " ~ parent ~ "(tstream);");
    } 
    return exp;
}

alias parseSimpleBinaryExp!(AsmLogOrExp, TokenType.DoublePipe, "parseAsmLogAndExp") parseAsmLogOrExp;
alias parseSimpleBinaryExp!(AsmLogAndExp, TokenType.DoubleAmpersand, "parseAsmOrExp") parseAsmLogAndExp;
alias parseSimpleBinaryExp!(AsmOrExp, TokenType.Pipe, "parseAsmXorExp") parseAsmOrExp;
alias parseSimpleBinaryExp!(AsmXorExp, TokenType.Pipe, "parseAsmAndExp") parseAsmXorExp;
alias parseSimpleBinaryExp!(AsmAndExp, TokenType.Ampersand, "parseAsmEqualExp") parseAsmAndExp;

AsmEqualExp parseAsmEqualExp(TokenStream tstream)
{
    auto exp = new AsmEqualExp();
    exp.location = tstream.peek.location;
    exp.lhs = parseAsmRelExp(tstream);
    if (tstream.peek.type == TokenType.DoubleAssign) {
        exp.equal = true;
        exp.rhs = parseAsmRelExp(tstream);
    } else if (tstream.peek.type == TokenType.BangAssign) {
        exp.equal = false;
        exp.rhs = parseAsmRelExp(tstream);
    }
    return exp;
}

AsmRelExp parseAsmRelExp(TokenStream tstream)
{
    auto exp = new AsmRelExp();
    exp.location = tstream.peek.location;
    exp.lhs = parseAsmShiftExp(tstream);
    switch (tstream.peek.type) {
    case TokenType.Less: exp.type = RelType.LT; break;
    case TokenType.LessAssign: exp.type = RelType.LTE; break;
    case TokenType.Greater: exp.type = RelType.GT; break;
    case TokenType.GreaterAssign: exp.type = RelType.GTE; break;
    default: break;
    }
    if (exp.type != RelType.None) {
        exp.rhs = parseAsmShiftExp(tstream);
    } 
    return exp;
}

AsmShiftExp parseAsmShiftExp(TokenStream tstream)
{
    auto exp = new AsmShiftExp();
    exp.location = tstream.peek.location;
    exp.lhs = parseAsmAddExp(tstream);
    switch (tstream.peek.type) {
    case TokenType.DoubleLess: exp.type = ShiftType.DoubleLeft; break;
    case TokenType.DoubleGreater: exp.type = ShiftType.DoubleRight; break;
    case TokenType.TripleGreater: exp.type = ShiftType.TripleRight; break;
    default: break;
    }
    if (exp.type != ShiftType.None) {
        exp.rhs = parseAsmAddExp(tstream);
    }
    return exp;
}

AsmAddExp parseAsmAddExp(TokenStream tstream)
{
    auto exp = new AsmAddExp();
    exp.location = tstream.peek.location;
    exp.lhs = parseAsmMulExp(tstream);
    if (tstream.peek.type == TokenType.Plus) {
        exp.addition = true;
        exp.rhs = parseAsmMulExp(tstream);
    } else if (tstream.peek.type == TokenType.Dash) {
        exp.addition = false;
        exp.rhs = parseAsmMulExp(tstream);
    }
    return exp;
}

AsmMulExp parseAsmMulExp(TokenStream tstream)
{
    auto exp = new AsmMulExp();
    exp.location = tstream.peek.location;
    exp.lhs = parseAsmBrExp(tstream);
    if (tstream.peek.type == TokenType.Asterix) {
        exp.type = MulType.Multiply;
    } else if (tstream.peek.type == TokenType.Slash) {
        exp.type = MulType.Divide;
    } else if (tstream.peek.type == TokenType.Percent) {
        exp.type = MulType.Modulus;
    }
    if (exp.type != MulType.None) {
        exp.rhs = parseAsmBrExp(tstream);
    }
    return exp;
}

AsmBrExp parseAsmBrExp(TokenStream tstream)
{
    auto exp = new AsmBrExp();
    exp.location = tstream.peek.location;
    exp.unaExp = parseAsmUnaExp(tstream);
    if (tstream.peek.type == TokenType.OpenBracket) {
        tstream.get();
        exp.exp = parseAsmExp(tstream);
        match(tstream, TokenType.CloseBracket);
    }
    return exp;
}

AsmUnaExp parseAsmUnaExp(TokenStream tstream)
{
    void matchptr()
    {
        if (tstream.peek.type != TokenType.Identifier && tstream.peek.value == "ptr") {
            throw new CompilerError(tstream.peek.location, "expected 'ptr'.");
        }
    }
    
    auto exp = new AsmUnaExp();
    exp.location = tstream.peek.location;
    switch (tstream.peek.type) {
    case TokenType.Identifier:
        switch (tstream.peek.value) {
        case "near":
            tstream.get();
            exp.prefix = SizePrefix.Near;
            matchptr();
            break;
        case "far":
            tstream.get();
            exp.prefix = SizePrefix.Far;
            matchptr();
            break;
        case "word":
            tstream.get();
            exp.prefix = SizePrefix.Word;
            matchptr();
            break;
        case "dword":
            tstream.get();
            exp.prefix = SizePrefix.DWord;
            matchptr();
            break;
        case "qword":
            tstream.get();
            exp.prefix = SizePrefix.QWord;
            matchptr();
            break;
        case "offsetof":
            tstream.get();
            exp.type = UnaType.Offset;
            break;
        case "seg":
            tstream.get();
            exp.type = UnaType.Seg;
            break;
        default:
            goto _parse_primary;
        }
        exp.exp = parseAsmExp(tstream);
        break;
    case TokenType.Byte:
        tstream.get();
        exp.prefix = SizePrefix.Byte;
        exp.exp = parseAsmExp(tstream);
        break;
    case TokenType.Short:
        tstream.get();
        exp.prefix = SizePrefix.Short;
        exp.exp = parseAsmExp(tstream);
        break;
    case TokenType.Int:
        tstream.get();
        exp.prefix = SizePrefix.Int;
        exp.exp = parseAsmExp(tstream);
        break;
    case TokenType.Float:
        tstream.get();
        exp.prefix = SizePrefix.Float;
        exp.exp = parseAsmExp(tstream);
        break;
    case TokenType.Double:
        tstream.get();
        exp.prefix = SizePrefix.Double;
        exp.exp = parseAsmExp(tstream);
        break;
    case TokenType.Real:
        tstream.get();
        exp.prefix = SizePrefix.Real;
        exp.exp = parseAsmExp(tstream);
        break;
    case TokenType.Plus:
        tstream.get();
        exp.type = UnaType.Plus;
        exp.unaExp = parseAsmUnaExp(tstream);
        break;
    case TokenType.Dash:
        tstream.get();
        exp.type = UnaType.Minus;
        exp.unaExp = parseAsmUnaExp(tstream);
        break;
    case TokenType.Bang:
        tstream.get();
        exp.type = UnaType.LogicalNot;
        exp.unaExp = parseAsmUnaExp(tstream);
        break;
    case TokenType.Tilde:
        tstream.get();
        exp.type = UnaType.BitwiseNot;
        exp.unaExp = parseAsmUnaExp(tstream);
        break;
    default:
    _parse_primary:
        exp.primaryExp = parseAsmPrimaryExp(tstream);
        break;
    }
    return exp;
}

AsmPrimaryExp parseAsmPrimaryExp(TokenStream tstream)
{
    auto exp = new AsmPrimaryExp();
    exp.location = tstream.peek.location;
    if (tstream.peek.type == TokenType.Identifier) {
        if (tstream.peek.value == "__LOCAL_SIZE") {
            tstream.get();
            exp.type = PrimaryType.__LOCAL_SIZE;
        }
        if (X86_REGISTERS.contains(tstream.peek.value)) {
            exp.type = PrimaryType.Register;
            exp.register = tstream.peek.value;
            tstream.get();
        }
        exp.type = PrimaryType.DotIdentifier;
        if (tstream.lookahead(1).type == TokenType.Dot) {
            exp.qualifiedName = parseQualifiedName(tstream);
        } else {
            exp.name = parseIdentifier(tstream);
        }
    } else if (tstream.peek.type == TokenType.Dollar) {
        tstream.get();
        exp.type = PrimaryType.Dollar;
    } else if (tstream.peek.type == TokenType.IntegerLiteral) {
        exp.type = PrimaryType.IntegerLiteral;
        exp.integerLiteral = parseIntegerLiteral(tstream);
    } else if (tstream.peek.type == TokenType.FloatLiteral) {
        exp.type = PrimaryType.FloatLiteral;
        exp.floatLiteral = parseFloatLiteral(tstream);
    } else {
        throw new CompilerError(tstream.peek.location, "expected primary expression.");
    }
    return exp;
}
