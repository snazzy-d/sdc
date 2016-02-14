#!/usr/bin/env python

import os
llvmconfig = os.getenv('LLVM_CONFIG', 'llvm-config')

import subprocess
llvm_source_root = subprocess.check_output([llvmconfig, "--src-root"]).strip()

# Make sure we can find the lit package.
import sys
sys.path.insert(0, os.path.join(llvm_source_root, 'utils', 'lit'))

if __name__=='__main__':
    import lit
    lit.main()
