module sdc.repl;
version (SDCREPL):

import std.process;
import std.stdio;

import llvm.c.Core;
import llvm.c.Initialization;

import sdc.aglobal;
import sdc.lexer;
import sdc.location;
import sdc.source;
import sdc.util;
import sdc.ast.base;
import sdc.parser.base;
import sdc.parser.expression;
import sdc.gen.expression;
import sdc.gen.sdcmodule;

extern (C) void _Z18LLVMInitializeCoreP22LLVMOpaquePassRegistry(LLVMPassRegistryRef);

string premain = "void main() {";
string postmain = "}";

void main(string[] args)
{
    auto passRegistry = LLVMGetGlobalPassRegistry();
    _Z18LLVMInitializeCoreP22LLVMOpaquePassRegistry(passRegistry);  // TMP !!!
    LLVMInitializeCodeGen(passRegistry);
    
    globalInit("x86-64");
    
    auto location = Location("/dev/null");
    auto bitcode = temporaryFilename(".bc"), assembly = temporaryFilename(".s"), object = temporaryFilename(".o");
    
    auto namesrc = new Source("fake.module", location);
    auto namelex = lex(namesrc);
    namelex.get(); // skip BEGIN
    auto name = parseQualifiedName(namelex);
    auto mod = new Module(name);
    
    while (true) {
        auto input = stdin.readln();
        auto src = new Source(input, location);
        auto tstream = lex(src);
        tstream.get();  // skip BEGIN
        auto exp = parseExpression(tstream);
        auto val = genExpression(exp, mod);
        writeln("=> ", val.knownInt);
    }
}
