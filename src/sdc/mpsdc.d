/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.mpsdc;
version (SDCMULTIPASS):

import std.stdio : writeln, stderr, stdout;
import std.file : exists;

import sdc.compilererror : CompilerError;
import sdc.lexer : lex;
import sdc.source : Source;
import sdc.tokenstream : TokenStream;


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
    tstream.printTo(stdout);
}
