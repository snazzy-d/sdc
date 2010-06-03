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
}

class ModuleDeclaration : Node
{
    QualifiedName name;
}
