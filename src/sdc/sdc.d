/**
 * Copyright 2010 Bernard Helyer
 * 
 * This file is part of SDC.
 * 
 * SDC is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
module sdc.sdc;

import std.conv;
import std.stdio;
import std.string;
import std.getopt;
import std.process : system;
import std.c.stdlib;

import llvm.c.Analysis;
import llvm.c.BitWriter;
import llvm.c.Core;
import llvm.c.transforms.Scalar;

import sdc.source;
import sdc.tokenstream;
import sdc.lexer;
import sdc.compilererror;
import sdc.info;
import sdc.global;
import ast = sdc.ast.all;
import sdc.parser.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;

enum OutputMode
{
    Bitcode,
    NativeAssembly
}

int main(string[] args)
{
    bool printTokens;
    auto outputMode = OutputMode.Bitcode;
    string march = "x86-64";
    
    try {
        getopt(args,
               "help", () { usage(); exit(0); },
               "version", () { stdout.writeln(VERSION_STRING); exit(0); },
               "output", 
               (string option, string arg)
               {
                   switch (arg) {
                   case "bitcode":
                       outputMode = OutputMode.Bitcode;
                       break;
                   case "native-assembly":
                       outputMode = OutputMode.NativeAssembly;
                       break;
                   default:
                       error(format("unknown output type '%s'.", arg));
                   }
               },
               "march", &march,
               "version-identifier", (string option, string arg) { setVersion(arg); },
               "debug-identifier", (string option, string arg) { setDebug(arg); },
               "version-level", &versionLevel,
               "debug-level", &debugLevel,
               "debug", () { isDebug = true; },
               "release", () { isDebug = false; },
               "unittest", () { unittestsEnabled = true; },
               "print-tokens", &printTokens
               );
    } catch (CompilerError) {
        exit(1);
    } catch (Exception) {
        stderr.writeln("bad command line.");
        exit(1);
    }
          
    if (args.length == 1) {
        usage(); exit(1);
    }
    
    bool errors;
    foreach (arg; args[1 .. $]) {
        auto source = new Source(arg);
        TokenStream tstream;
        ast.Module aModule;
        Module gModule;
        scope (exit) if (gModule !is null) gModule.dispose();
        try {
            tstream = lex(source);
            aModule = parseModule(tstream);
            gModule = genModule(aModule);
        } catch (CompilerError) {
            errors = true;
            continue;
        }
        
        if (printTokens) tstream.printTo(stdout);
        gModule.verify();
        gModule.optimise();
        gModule.dump();
        if (outputMode == OutputMode.Bitcode) {
            gModule.writeBitcodeToFile("test.bc");
            system("llvm-ld -native test.bc");
        } else if (outputMode == OutputMode.NativeAssembly) {
            gModule.writeBitcodeToFile("test.bc");
            gModule.writeNativeAssemblyToFile("test.bc", "test.s", march);
            system("gcc test.s");
        }
    }

    return errors ? 1 : 0;
}


void usage()
{
    writeln("sdc [options] modules");
    writeln("  --help:                print this message.");
    writeln("  --version:             print version information to stdout.");
    writeln("  --output:              output input module as: (default is bitcode)");
    writeln("                         ['bitcode', 'native-assembly']");
    writeln("  --march:               if output (see above) is set to native-assembly,");
    writeln("                         the argument to march is passed to llc. See the");
    writeln("                         output of `llc --version` for supported archs.");
    writeln("                         Defaults to 'x86-64'.");
    writeln("  --version-identifier:  specify the given version identifier.");
    writeln("  --debug-identifier:    specify the given debug identifier.");
    writeln("  --version-level:       set the version level to the given integer.");
    writeln("  --debug-level:         set the debug level to the given integer.");
    writeln("  --debug:               compile in debug mode (defaults on).");
    writeln("  --release:             don't compile in debug mode (defaults off).");
    writeln("  --unittest:            compile in unittests (defaults off)."); 
    writeln("  --print-tokens:        print the results of tokenisation to stdout.");
}
