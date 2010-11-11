module sdc.ast.sdcpragma;

import sdc.ast.base;
import sdc.ast.expression;


// pragma \( Identifier , ArgumentList? \)
class Pragma : Node
{
    Identifier identifier;
    ArgumentList argumentList;  // Optional.
}
