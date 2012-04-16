/**
 * Copyright 2010-2012 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * 
 * This file is part of SDC.
 *
 * See LICENCE for copying information.
 */
module sdc.sdc;
version (SDCCOMPILER):

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
import sdc.aglobal;
import sdc.terminal;
import sdc.extract;
import ast = sdc.ast.all;
import sdc.parser.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.sdcimport;
import sdc.gen.declaration;
import sdc.interpreter.base;

version = SDC_x86_default;

int main(string[] args)
{
    auto passRegistry = LLVMGetGlobalPassRegistry();
    LLVMInitializeCore(passRegistry);
    LLVMInitializeCodeGen(passRegistry);
    try {
        int retval = realmain(args);
        return retval;
    } catch (CompilerError topError) {
        auto error = topError;
        do {
            stderr.writeln(error.msg);
            
            if(error.location.filename !is null) {
                outputCaretDiagnostics(error.location, error.fixHint);
            }
        } while ((error = error.more) !is null);
        
        version(sdc_pass_on_error) {
            throw topError;
        } else {
            return 1;
        }
    }
}

int realmain(string[] args)
{
    bool skipLink = false, optimise = false, saveTemps = false, interpret = false;
    string outputName = "";
    version (OSX) string gcc = "clang";
    else string gcc = "gcc";
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
        // WORKAROUND 2.058
        void disableWarning(string, string arg) { disabledWarnings ~= cast(Warning) parse!uint(arg); }
        void warningAsError(string, string arg) { errorWarnings ~= cast(Warning) parse!uint(arg); }
        void setArch(string, string arg) { arch = arg; }
        void addImport(string, string arg) { importPaths ~= arg; }
        void setVersionI(string, string arg) { setVersion(arg); }
        void setDebugI(string, string arg) { setDebug(arg); }
        getopt(args,
               std.getopt.config.caseSensitive,
               "help|h", delegate { usage(); exit(0); },
               "version|v",  delegate { writeln(VERSION_STRING); exit(0); },
               "version-identifier", &setVersionI,
               "debug-identifier", &setDebugI,
               "debug", delegate { isDebug = true; },
               "release", delegate { isDebug = false; },
               "unittest", delegate { unittestsEnabled = true; },
               "no-colour-print", delegate { coloursEnabled = false; },
               "I", &addImport,
               "gcc", &gcc,
               "arch", &setArch,
               "m64", delegate { arch = "x86-64"; },
               "m32", delegate { arch = "x86"; },
               "nw", &disableAllWarnings,
               "we", &treatWarningsAsErrors,
               "disable-warning", &disableWarning,
               "warning-as-error", &warningAsError,
               "c", &skipLink,
               "run", &interpret,
               "O", &optimise,
               "o", &outputName,
               "V", delegate { verboseCompile = true; },
               "save-temps", &saveTemps,
               "pic", &PIC
               );
    } catch (Exception e) {
        throw new CompilerError(e.msg);
    }
    globalInit(arch);
    
    if (args.length == 1) {
        stderr.writeln(args[0], ": error: no input files.");
        stderr.writeln("try --help or man sdc.");
        return 1;
    }
    
    if (skipLink && outputName != "" && args.length > 2) {
        throw new CompilerError("multiple modules cannot have the same output name, unless being linked into an executable.");
    }

    verbosePrint(VERSION_STRING);
    verbosePrint("Reading config file from '" ~ confLocation ~ "'.");
    verbosePrint("Effective command line: '" ~ to!string(argsCopy) ~ "'.");
    
    struct Assembly { string filename; bool compiledByThisInstance; string canonical; } 
    Assembly[] assemblies;
    foreach (arg; args[1 .. $]) {
        auto ext = extension(arg);
        
        switch(ext){
        case ".o":
            assemblies ~= Assembly(arg, false, "");
            break;
                
        case ".d", ".di":
            if (!file.exists(arg)) {
                throw new CompilerError(format(`source "%s" could not be found.`, arg));
            }
            if (!file.isFile(arg)) {
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
    
    TranslationUnit[] tus = getTranslationUnits();
    if (interpret && tus.length != 1) {
        throw new CompilerError("with --run, exactly one module must be passed to SDC.");
    } else if (interpret) {
        assert(tus.length == 1);
        auto interpreter = new Interpreter(tus[0]);
        i.Value retval = interpreter.callMain();
        return retval.val.Int;
    }
    
    auto extensionRegex = regex(r"d(i)?$", "i");
    foreach (translationUnit; tus) with (translationUnit) {
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
        
        
        auto canonicalBitcode  = replace(filename, extensionRegex, "bc");
        auto asBitcode  = temporaryFilename(".bc");
        auto canonicalAssembly = replace(filename, extensionRegex, "s");
        auto asAssembly = temporaryFilename(".s");
        auto canonicalObject   = replace(filename, extensionRegex, "o");
        auto asObject   = temporaryFilename(".o");
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
        assemblies ~= Assembly(asObject, true, canonicalObject);
        
        if (file.exists(asBitcode)) {
            if (saveTemps) file.copy(asBitcode, canonicalBitcode);
            file.remove(asBitcode);
        }
        if (file.exists(asAssembly)) {
            if (saveTemps) file.copy(asAssembly, canonicalAssembly);
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
            linkCommand ~= `"` ~ assembly.filename ~ `" `;
        }
        
        verbosePrint(linkCommand);
        system(linkCommand);
        
        foreach (assembly; assemblies) {
            if (file.exists(assembly.filename) && assembly.compiledByThisInstance) {
                if (saveTemps) file.copy(assembly.filename, assembly.canonical);
                file.remove(assembly.filename);
            }
        }
    } else {
        foreach (assembly; assemblies) if (assembly.compiledByThisInstance && file.exists(assembly.filename)) {
            file.copy(assembly.filename, assembly.canonical);
            file.remove(assembly.filename);
        }
    }
    
    return 0;
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
    writeln("  --save-temps:          leave temporary files on disk.");
    writeln("  --gcc:                 set the command for running GCC.");
    writeln("  --arch:                set the architecture to generate code for. See llc(1).");
    writeln("  --pic:                 generate position independent code.");
    writeln("  --nw:                  disable all warnings.");
    writeln("  --we:                  treat all warnings as errors.");
    writeln("  --disable-warning:     disable a specific warning.");
    writeln("  --warning-as-error:    treat a specific warning as an error.");
    writeln("  --run:                 interpret, don't compile.");
    writeln("  -m32:                  synonym for '--arch=x86'.");
    writeln("  -m64:                  synonym for '--arch=x86-64'.");
    writeln("  -O:                    optimise the output.");
    writeln("  -I:                    search path for import directives.");
    writeln("  -c:                    just compile, don't link.");
    writeln("  -o:                    name of the output file. (-o=filename)");
    writeln("  -V:                    compile with verbose output.");
}
