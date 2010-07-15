/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.extract;

import sdc.ast.base;


string extractIdentifier(Identifier identifier)
{
    return identifier.value;
}
