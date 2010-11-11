/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcpragma;

import sdc.ast.base;
import sdc.ast.expression;


// pragma \( Identifier , ArgumentList? \)
class Pragma : Node
{
    Identifier identifier;
    ArgumentList argumentList;  // Optional.
}
