/*===------- llvm/Config/llvm-config.h - llvm configuration -------*- C -*-===*/
/*                                                                            */
/* Part of the LLVM Project, under the Apache License v2.0 with LLVM          */
/* Exceptions.                                                                */
/* See https://llvm.org/LICENSE.txt for license information.                  */
/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception                    */
/*                                                                            */
/*===----------------------------------------------------------------------===*/

module llvm.c.config;

/* This file enumerates variables from the LLVM configuration so that they
   can be in exported headers and won't override package specific directives.
   This is a C header that can be included in the llvm-c headers. */
private auto genConfig(string Path)() {
  string[string] config;

  import std.algorithm, std.range, std.string;
  foreach (def; import(Path).splitLines().filter!(l => l.startsWith("#define "))
                            .map!(l => l[8 .. $].split(' '))) {
    if (def.length != 2) {
      continue;
    }

    config[def[0]] = def[1];
  }

  return config;
}

private enum Config = genConfig!"llvm/Config/llvm-config.h"();

private auto unwrapString(string Name)() {
  import std.format;
  static assert((Name in Config) !is null,
                format!"Impossible to find LLVM configuration %s."(Name));

  auto asLiteral() {
    auto raw = Config[Name];
    if (raw[0] == '"') {
      return raw;
    }

    return stringify(raw);
  }

  return mixin(asLiteral());
}

/* Target triple LLVM will generate code for by default */
enum LLVM_DEFAULT_TARGET_TRIPLE = unwrapString!"LLVM_DEFAULT_TARGET_TRIPLE";

/* Host triple LLVM will be executed on */
enum LLVM_HOST_TRIPLE = unwrapString!"LLVM_HOST_TRIPLE";

/* LLVM architecture name for the native architecture, if available */
enum LLVM_NATIVE_ARCH = unwrapString!"LLVM_NATIVE_ARCH";

/* LLVM name for the native AsmParser init function, if available */
enum LLVM_NATIVE_ASMPARSER = unwrapString!"LLVM_NATIVE_ASMPARSER";

/* LLVM name for the native AsmPrinter init function, if available */
enum LLVM_NATIVE_ASMPRINTER = unwrapString!"LLVM_NATIVE_ASMPRINTER";

/* LLVM name for the native Disassembler init function, if available */
enum LLVM_NATIVE_DISASSEMBLER = unwrapString!"LLVM_NATIVE_DISASSEMBLER";

/* LLVM name for the native Target init function, if available */
enum LLVM_NATIVE_TARGET = unwrapString!"LLVM_NATIVE_TARGET";

/* LLVM name for the native TargetInfo init function, if available */
enum LLVM_NATIVE_TARGETINFO = unwrapString!"LLVM_NATIVE_TARGETINFO";

/* LLVM name for the native target MC init function, if available */
enum LLVM_NATIVE_TARGETMC = unwrapString!"LLVM_NATIVE_TARGETMC";

private:

string toCharLit(char c) {
  switch (c) {
    case '\0':
      return "\\0";

    case '\'':
      return "\\'";

    case '"':
      return "\\\"";

    case '\\':
      return "\\\\";

    case '\a':
      return "\\a";

    case '\b':
      return "\\b";

    case '\t':
      return "\\t";

    case '\v':
      return "\\v";

    case '\f':
      return "\\f";

    case '\n':
      return "\\n";

    case '\r':
      return "\\r";

    default:
      import std.ascii;
      if (isPrintable(c)) {
        return [c];
      }

      static char toHexChar(ubyte n) {
        return ((n < 10) ? (n + '0') : (n - 10 + 'a')) & 0xff;
      }

      static string toHexString(ubyte c) {
        return [toHexChar(c >> 4), toHexChar(c & 0x0f)];
      }

      return "\\x" ~ toHexString(c);
  }
}

auto stringify(string s) {
  import std.algorithm, std.format, std.string;
  return format!`"%-(%s%)"`(s.representation.map!(c => toCharLit(c)));
}
