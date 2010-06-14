/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */
module sdc.asttojson.declaration;

import sdc.ast.declaration;
import sdc.asttojson.base;

JSONObject prettyDeclaration(Declaration declaration)
{
    auto root = new JSONObject();
    root["alias"] = new JSONString(declaration.isAlias ? "true" : "false");
    return root;
}
