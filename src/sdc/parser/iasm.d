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
    SizePrefix sizePrefix = SizePrefix.None;
}

enum OperandType
{
    Register,
}

class Operand
{
    Location location;
}

class AsmExp
{
    AsmLogOrExp logOrExp;
    AsmExp lhs;  // Optional.
    AsmExp rhs;  // Optional.
}

class AsmLogOrExp
{
    AsmLogAndExp lhs;
    AsmLogAndExp rhs;  // Optional.
}

class AsmLogAndExp
{
    AsmOrExp lhs;
    AsmOrExp rhs;  // Optional.
}

class AsmOrExp
{
    AsmXorExp lhs;
    AsmXorExp rhs;  // Optional.
}

class AsmXorExp
{
    AsmAndExp lhs;
    AsmAndExp rhs;  // Optional.
}

class AsmAndExp
{
    AsmEqualExp lhs;
    AsmEqualExp rhs;  // Optional.
}

class AsmEqualExp
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

class AsmRelExp
{
    RelType type;
    AsmShiftExp lhs;
    AsmShiftExp rhs;  // Optional.
}

class AsmShiftExp
{
}

class AsmAddExp
{
}

class AsmMulExp
{
}

class AsmBrExp
{
}

class AsmUnaExp
{
}

class AsmPrimaryExp
{
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
    tstream.getToken();
    opcode.sizePrefix = parseSizePrefix(tstream);
    return opcode;
}

SizePrefix parseSizePrefix(TokenStream tstream)
{
    void parsePtr()
    {
        auto ident = match(tstream, TokenType.Identifier);
        if (ident.value != "ptr") {
            throw new CompilerError(ident.location, "expected 'ptr'.");
        }
    }
    
    switch (tstream.peek.type) {
    case TokenType.Identifier:
        switch (tstream.peek.value) {
        case "near":
            tstream.getToken();
            parsePtr();
            return SizePrefix.Near;
        case "far":
            tstream.getToken();
            parsePtr();
            return SizePrefix.Far;
        case "word":
            tstream.getToken();
            parsePtr();
            return SizePrefix.Word;
        case "dword":
            tstream.getToken();
            parsePtr();
            return SizePrefix.DWord;
        case "qword":
            tstream.getToken();
            parsePtr();
            return SizePrefix.QWord;
        default:
            return SizePrefix.None;
        }
    case TokenType.Byte:
        tstream.getToken();
        parsePtr();
        return SizePrefix.Byte;
    case TokenType.Short:
        tstream.getToken();
        parsePtr();
        return SizePrefix.Short;
    case TokenType.Int:
        tstream.getToken();
        parsePtr();
        return SizePrefix.Int;
    case TokenType.Float:
        tstream.getToken();
        parsePtr();
        return SizePrefix.Float;
    case TokenType.Double:
        tstream.getToken();
        parsePtr();
        return SizePrefix.Double;
    case TokenType.Real:
        tstream.getToken();
        parsePtr();
        return SizePrefix.Real;
    default:
        return SizePrefix.None;
    }
}
