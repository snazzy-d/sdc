/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */
module sdc.ast.sdcmodule;

import std.path;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.base;


class Module : Node
{
    ModuleDeclaration moduleDeclaration;
    
    this(TokenStream tstream)
    {
        match(tstream, TokenType.Begin);
        moduleDeclaration = new ModuleDeclaration(tstream);
    }
}

class ModuleDeclaration : Node
{
    QualifiedName name;
    
    this(TokenStream tstream)
    {
        if (tstream.peek.type == TokenType.Module) {
            // Explicit module declaration.
            match(tstream, TokenType.Module);
            name = new QualifiedName(tstream);
            match(tstream, TokenType.Semicolon);
        } else {
            // Implicit module declaration.
            name = new QualifiedName(tstream, basename(tstream.filename, "." ~ getExt(tstream.filename)));
        }
    }
}
