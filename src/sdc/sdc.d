/**
 * Copyright 2010-2011 Bernard Helyer.
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

import std.algorithm;
import std.array;
import std.conv;
import std.range;
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
import llvm.c.Initialization;

import sdc.util;
import sdc.source;
import sdc.tokenstream;
import sdc.lexer;
import sdc.compilererror;
import sdc.info;
import sdc.global;
import sdc.terminal;
import sdc.extract;
import ast = sdc.ast.all;
import sdc.parser.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.sdcimport;
import sdc.gen.declaration;

version = SDC_x86_default;

extern (C) void _Z18LLVMInitializeCoreP22LLVMOpaquePassRegistry(LLVMPassRegistryRef);

int main(string[] args)
{
    auto passRegistry = LLVMGetGlobalPassRegistry();
    _Z18LLVMInitializeCoreP22LLVMOpaquePassRegistry(passRegistry);  // TMP !!!
    LLVMInitializeCodeGen(passRegistry);
    try {
        realmain(args);
    } catch (CompilerError topError) {
        auto error = topError;
        do {
            stderr.writeln(error.msg);
            
            if(error.hasLocation) {
                outputCaretDiagnostics(error.location, error.fixHint);
            }
        } while((error = error.more) !is null);
        
        version(sdc_pass_on_error) {
            throw topError;
    	} else {
            return 1;
        }
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
    foreach (i, arg; args) {
        // I figure people are more used to '-m32' and friends, so let them use 'em.
        if (arg == "--") {
            break;
        } else if (arg == "-m32") {
            args[i] = "--m32";
        } else if (arg == "-m64") {
            args[i] = "--m64";
        }
    }
    auto argsCopy = args.dup;
    try {
        getopt(args,
               std.getopt.config.caseSensitive,
               "help|h", { usage(); exit(0); },
               "version|v",  { writeln(VERSION_STRING); exit(0); },
               "version-identifier", (string option, string arg) { setVersion(arg); },
               "debug-identifier", (string option, string arg) { setDebug(arg); },
               "debug", { isDebug = true; },
               "release", { isDebug = false; },
               "unittest", { unittestsEnabled = true; },
               "no-colour-print", { coloursEnabled = false; },
               "I", (string, string path){ importPaths ~= path; },
               "optimise", &optimise,
               "gcc", &gcc,
               "arch", (string, string arg) { arch = arg; },
               "m64", { arch = "x86-64"; },
               "m32", { arch = "x86"; },
               "c", &skipLink,
               "o", &outputName,
               "V", { verboseCompile = true; },
               "save-temps", &saveTemps,
               "pic", &PIC,
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

    verbosePrint(VERSION_STRING);
    verbosePrint("Reading config file from '" ~ confLocation ~ "'.");
    verbosePrint("Effective command line: '" ~ to!string(argsCopy) ~ "'.");
    
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
            if (!file.isfile(arg)) {
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
        gModule = genModule(aModule, translationUnit);
    }
    
    foreach (translationUnit; getTranslationUnits()) with (translationUnit) {
        // Okay. Build ze functions!
        foreach (declDef; gModule.functionBuildList) {
            auto info = cast(DeclarationDefinitionInfo) declDef.userData;
            assert(info !is null);
            
            if (info.buildStage != ast.BuildStage.ReadyForCodegen || info.importedSymbol) {
                continue;
            }
            assert(declDef.type == ast.DeclarationDefinitionType.Declaration);
            genDeclaration(cast(ast.Declaration) declDef.node, declDef, gModule);
        }
        gModule.verify();
        verbosePrint(format("Module '%s' passes verification.", gModule.mod));
            
        assert(!match(filename, extensionRegex).empty);
        auto asBitcode  = replace(filename, extensionRegex, "bc");
        auto asAssembly = replace(filename, extensionRegex, "s");
        auto asObject   = replace(filename, extensionRegex, "o");
        gModule.arch = arch;
        gModule.writeBitcodeToFile(asBitcode);
        if (optimise) {
            gModule.optimiseBitcode(asBitcode);
        }
        gModule.writeNativeAssemblyToFile(asBitcode, asAssembly);
        
        auto compileCommand = gcc ~ ((arch == "x86") ? " -m32 " : "") ~ " -c -o ";
        if (skipLink && outputName != "") {
            asObject = outputName;
        }
        compileCommand ~= asObject;
        compileCommand ~= " " ~ asAssembly;
        
        verbosePrint(compileCommand);
        system(compileCommand);
        assemblies ~= asObject;
        
        if (!saveTemps) {
            if (file.exists(asBitcode)) {
                file.remove(asBitcode);
            }
            if (file.exists(asAssembly)) {
                file.remove(asAssembly);
            }
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
        
        verbosePrint(linkCommand);
        system(linkCommand);
        
        if (!saveTemps) {
            foreach (assembly; assemblies) {
                if (file.exists(assembly)) {
                    file.remove(assembly);
                }
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
    writeln("  --pic:                 generate position independent code.");
    writeln("  -m32:                  synonym for '--arch=x86'.");
    writeln("  -m64:                  synonym for '--arch=x86-64'.");
    writeln("  -I:                    search path for import directives.");
    writeln("  -c:                    just compile, don't link.");
    writeln("  -o:                    name of the output file. (-o=filename)");
    writeln("  -V:                    compile with verbose output.");
}
