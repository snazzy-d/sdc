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
import std.regex;
import std.stdio;
import std.string;
import std.getopt;
import std.path;
import std.process : system;
import std.c.stdlib;

import llvm.c.Core;

import sdc.util;
import sdc.source;
import sdc.tokenstream;
import sdc.lexer;
import sdc.compilererror;
import sdc.info;
import sdc.global;
import ast = sdc.ast.all;
import sdc.extract.base;
import sdc.parser.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.sdcimport;


int main(string[] args)
{
    int retval;
    try {
        realmain(args);
    } catch (CompilerError) {
        retval = 1;
    }
    return retval;
}

void realmain(string[] args)
{
    bool justCompile;
    try {
        getopt(args,
               "help", () { usage(); exit(0); },
               "version", () { stdout.writeln(VERSION_STRING); exit(0); },
               "version-identifier", (string option, string arg) { setVersion(arg); },
               "debug-identifier", (string option, string arg) { setDebug(arg); },
               "debug", () { isDebug = true; },
               "release", () { isDebug = false; },
               "unittest", () { unittestsEnabled = true; },
               "c", &justCompile
               );
    } catch (Exception) {
        stderr.writeln("bad command line.");
        throw new CompilerError();
    }
          
    if (args.length == 1) {
        usage();
        return;
    }
    
    string[] assemblies;
    foreach (arg; args[1 .. $]) {
        auto ext = getExt(arg);
        if (ext == "o") {
            assemblies ~= arg;
            continue;
        }
        
        if (ext != "d" && ext != "di") {
            stderr.writeln("unknown extension '", ext, "'.");
            throw new CompilerError();
        }
        auto translationUnit = new TranslationUnit();
        translationUnit.tusource = TUSource.Compilation;
        translationUnit.filename = arg;
        translationUnit.source = new Source(arg);
        translationUnit.tstream = lex(translationUnit.source);
        translationUnit.aModule = parseModule(translationUnit.tstream);
        auto name = extractQualifiedName(translationUnit.aModule.moduleDeclaration.name);
        addTranslationUnit(name, translationUnit);
    }
    
    auto extensionRegex = regex(r"d(i)?$", "i");
    int moduleCompilationFailures, oldModuleCompilationFailures = -1;
    bool lastPass;
    while (true) {
        moduleCompilationFailures = 0;
        foreach (translationUnit; getTranslationUnits()) with (translationUnit) {
            if (!compile || state == ModuleState.Complete) {
                continue;
            }
            gModule = genModule(aModule);
            if (gModule is null) {
                moduleCompilationFailures++;
                continue;
            } else {
                state = ModuleState.Complete;
            }
            gModule.verify();
            gModule.optimise();
            
            assert(!match(filename, extensionRegex).empty);
            auto asBitcode  = replace(filename, extensionRegex, "bc");
            auto asAssembly = replace(filename, extensionRegex, "s");
            auto asObject   = replace(filename, extensionRegex, "o");
            gModule.writeBitcodeToFile(asBitcode);
            gModule.writeNativeAssemblyToFile(asBitcode, asAssembly);
            auto compileCommand = "gcc -c -o " ~ asObject ~ " " ~ asAssembly;
            system(compileCommand);
            assemblies ~= asObject;
        }
        
        if (moduleCompilationFailures == 0) {
            break;
        } else if (oldModuleCompilationFailures == moduleCompilationFailures) {
            if (lastPass) {
                panic("A simple error has occured. However, SDC is in flux at the moment, and this is a temporary error.");
            } else {
                lastPass = true;
            }
        } else {
            lastPass = false;
            oldModuleCompilationFailures = moduleCompilationFailures;
        }
    }
    
    
    if (!justCompile) {
        auto linkCommand = "gcc -o a.out ";
        foreach (assembly; assemblies) {
            linkCommand ~= assembly ~ " ";
        }
        system(linkCommand);
    }
}

void addImplicitImports()
{

}

void usage()
{
    writeln("sdc [options] modules");
    writeln("  --help:                print this message.");
    writeln("  --version:             print version information to stdout.");
    writeln("  --version-identifier:  specify the given version identifier.");
    writeln("  --debug-identifier:    specify the given debug identifier.");
    writeln("  --version-level:       set the version level to the given integer.");
    writeln("  --debug-level:         set the debug level to the given integer.");
    writeln("  --debug:               compile in debug mode (defaults on).");
    writeln("  --release:             don't compile in debug mode (defaults off).");
    writeln("  --unittest:            compile in unittests (defaults off)."); 
    writeln("  -c:                    just compile, don't link.");
}
