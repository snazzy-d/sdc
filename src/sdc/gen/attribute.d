/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.attribute;

import std.conv;
import std.string;

import sdc.global;
import sdc.util;
import sdc.compilererror;
import ast = sdc.ast.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.type;
