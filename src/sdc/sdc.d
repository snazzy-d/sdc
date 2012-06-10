/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.mpsdc;

import std.stdio : writeln, stderr, stdout;
import std.file : exists;

import sdc.compilererror;
import sdc.lexer;
import sdc.source;
import sdc.tokenstream;
import sdc.parser.base;
import sdc.ast.sdcmodule;

import sdc.pass.pure_simplify : pureSimplify;


int main(string[] args)
{
    if (args.length == 1) {
        stderr.writeln("usage: sdc file");
        return 1;
    }

    foreach (file; args[1..$]) {
        compile(file);
    }

    return 0;
}

void compile(string filename)
{
    auto src = new Source(filename);
    TokenStream tstream = lex(src);
    Module ast = parse(tstream);
    ast = pureSimplify(ast);
}
