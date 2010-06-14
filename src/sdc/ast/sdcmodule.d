/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 * 
 * ast/sdcmodule.d: top level AST definitions.
 */
module sdc.ast.sdcmodule;

import std.path;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.base;


class Module : Node
{
    ModuleDeclaration moduleDeclaration;
    DeclarationDefinition[] declarationDefinitions;
}

// module QualifiedName ;
class ModuleDeclaration : Node
{
    QualifiedName name;
}

class DeclarationDefinition : Node
{
}
