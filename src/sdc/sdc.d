/**
 * Copyright 2010 SDC Authors. See AUTHORS for more details.
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
import sdc.terminal;
import ast = sdc.ast.all;
import sdc.extract.base;
import sdc.parser.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.sdcimport;

bool colouredOutputDisabled = false;

int main(string[] args)
{
    try {
        realmain(args);
    } catch (CompilerError error) {
        stderr.writeln(error.msg);
        
        if(error.hasLocation) {
            outputCaretDiagnostics(error.location, colouredOutputDisabled);
        }
        return 1;
    }
    return 0;
}

void realmain(string[] args)
{
    bool skipLink = false;
    string outputName = "";
    try {
        getopt(args,
               "help|h", () { usage(); exit(0); },
               "version|v", () { writeln(VERSION_STRING); exit(0); },
               "version-identifier", (string option, string arg) { setVersion(arg); },
               "debug-identifier", (string option, string arg) { setDebug(arg); },
               "debug", () { isDebug = true; },
               "release", () { isDebug = false; },
               "unittest", () { unittestsEnabled = true; },
               "c", &skipLink,
               "o", &outputName,
               "no-colour-print", &colouredOutputDisabled
               );
    } catch (Exception e) {
        throw new CompilerError(e.msg);
    }
    
    if (args.length == 1) {
        usage();
        return;
    }
    
    if (skipLink && outputName != "" && args.length > 2) {
        throw new CompilerError("multiple modules cannot have the same output name, unless being linked into an executable.");
    }
    
    string[] assemblies;
    foreach (arg; args[1 .. $]) {
        auto ext = getExt(arg);
        
        switch(ext){
        case "o":
            assemblies ~= arg;
            break;
                
        case "d", "di":
            auto translationUnit = new TranslationUnit();
            translationUnit.tusource = TUSource.Compilation;
            translationUnit.filename = arg;
            translationUnit.source = new Source(arg);
            translationUnit.tstream = lex(translationUnit.source);
            translationUnit.aModule = parseModule(translationUnit.tstream);
            auto name = extractQualifiedName(translationUnit.aModule.moduleDeclaration.name);
            addTranslationUnit(name, translationUnit);
            break;
        
        default:
            throw new CompilerError(format(`unknown extension '%s' ("%s")`, ext, arg));
        }
    }
    
    // v Good lord!! v
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
            auto compileCommand = "gcc -c -o " ~ (outputName == "" ? asObject : outputName) ~ " " ~ asAssembly;
            system(compileCommand);
            assemblies ~= asObject;
        }
        
        if (moduleCompilationFailures == 0) {
            break;
        } else if (oldModuleCompilationFailures == moduleCompilationFailures) {
            if (lastPass) {
                throw new CompilerPanic("A simple error has occured. However, SDC is in flux at the moment, and this is a temporary error.");
            } else {
                lastPass = true;
            }
        } else {
            lastPass = false;
            oldModuleCompilationFailures = moduleCompilationFailures;
        }
    }
    // ^ Good lord!! ^
    
    string linkCommand = "gcc -o ";
    if (!skipLink) {
        if (outputName == "") {
            version (Windows) {
                linkCommand ~= "a.exe ";
            } else {
                linkCommand ~= "a.out ";
            }
        } else {
            linkCommand ~= outputName ~ " ";
        }
        
        foreach (assembly; assemblies) {
            linkCommand ~= `"` ~ assembly ~ `" `;
        }
        
        system(linkCommand);
    }
}

void usage()
{
    writeln("sdc [options] modules");
    writeln("  --help|-h:             print this message.");
    writeln("  --version|-v:          print version information to stdout.");
    writeln("  --version-identifier:  specify the given version identifier.");
    writeln("  --debug-identifier:    specify the given debug identifier.");
    writeln("  --debug:               compile in debug mode (defaults on).");
    writeln("  --release:             don't compile in debug mode (defaults off).");
    writeln("  --unittest:            compile in unittests (defaults off)."); 
    writeln("  -c:                    just compile, don't link.");
    writeln("  -o:                    name of the output file.");
}
