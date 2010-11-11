module sdc.ast.sdcpragma;

import sdc.ast.base;
import sdc.ast.expression;


class Pragma : Node
{
    Identifier identifier;
    ArgumentList argumentList;  // Optional.
}
