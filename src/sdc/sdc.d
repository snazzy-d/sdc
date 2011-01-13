/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
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
import file = std.file;
import std.c.stdlib;

import llvm.Ext;
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

version = SDC_x86_default;

int main(string[] args)
{
    try {
        realmain(args);
    } catch (CompilerError error) {
        do {
            stderr.writeln(error.msg);
            
            if(error.hasLocation) {
                outputCaretDiagnostics(error.location, error.fixHint);
            }
        } while((error = error.more) !is null);
        
        return 1;
    }
    return 0;
}

void realmain(string[] args)
{
    bool skipLink = false, optimise = false, saveTemps = false;
    string outputName = "";
    string gcc = "gcc";
    version (SDC_x86_default) {
        string arch = "x86";
    } else {
        string arch = "x86-64";
    }
    
    loadConfig(args);
    try {
        getopt(args,
               std.getopt.config.caseSensitive,
               "help|h", () { usage(); exit(0); },
               "version|v", () { writeln(VERSION_STRING); exit(0); },
               "version-identifier", (string option, string arg) { setVersion(arg); },
               "debug-identifier", (string option, string arg) { setDebug(arg); },
               "debug", () { isDebug = true; },
               "release", () { isDebug = false; },
               "unittest", () { unittestsEnabled = true; },
               "no-colour-print", (){ coloursEnabled = false; },
               "I", (string, string path){ importPaths ~= path; },
               "optimise", &optimise,
               "gcc", &gcc,
               "arch", &arch,
               "m32", () { arch = "x86"; },
               "m64", () { arch = "x86-64"; },
               "c", &skipLink,
               "o", &outputName,
               "save-temps", &saveTemps
               );
    } catch (Exception e) {
        throw new CompilerError(e.msg);
    }
    globalInit(arch);
    
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
            if (!file.exists(arg)) {
                throw new CompilerError(format(`source "%s" could not be found.`, arg));
            }
            if(!file.isfile(arg)) {
                throw new CompilerError(format(`source "%s" is not a file.`, arg));
            }
        
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
    
    auto extensionRegex = regex(r"d(i)?$", "i");
    foreach (translationUnit; getTranslationUnits()) with (translationUnit) {
        if (!compile) {
            continue;
        }
        gModule = genModule(aModule);
        gModule.verify();
        if (optimise) gModule.optimise();
        
        assert(!match(filename, extensionRegex).empty);
        auto asBitcode  = replace(filename, extensionRegex, "bc");
        auto asAssembly = replace(filename, extensionRegex, "s");
        auto asObject   = replace(filename, extensionRegex, "o");
        gModule.arch = arch;
        gModule.writeBitcodeToFile(asBitcode);
        gModule.writeNativeAssemblyToFile(asBitcode, asAssembly);
        
        auto compileCommand = gcc ~ ((arch == "x86") ? " -m32 " : "") ~ " -c -o ";
        if (skipLink && outputName != "") {
            asObject = outputName;
        }
        compileCommand ~= asObject;
        compileCommand ~= " " ~ asAssembly;
        
        system(compileCommand);
        assemblies ~= asObject;
        
        if (!saveTemps) {
            file.remove(asBitcode);
            file.remove(asAssembly);
        }
    }
    
    string linkCommand = gcc ~ ((arch == "x86") ? " -m32 " : "") ~ " -o ";
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
        
        if (!saveTemps) {
            foreach (assembly; assemblies) {
                file.remove(assembly);
            }
        }
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
    writeln("  --no-colour-print:     don't apply colour to diagnostic output.");
    writeln("  --optimise:            optimise the output.");
    writeln("  --save-temps:          leave temporary files on disk.");
    writeln("  --gcc:                 set the command for running GCC.");
    writeln("  --arch:                set the architecture to generate code for. See llc(1).");
    writeln("  --m32:                 synonym for '--arch=x86'.");
    writeln("  --m64:                 synonym for '--arch=x86-64'.");
    writeln("  -I:                    search path for import directives.");
    writeln("  -c:                    just compile, don't link.");
    writeln("  -o:                    name of the output file.");
}
