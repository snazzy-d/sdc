/*===-- llvm-c/blake3.h - BLAKE3 C Interface ----------------------*- C -*-===*\
|*                                                                            *|
|* Released into the public domain with CC0 1.0                               *|
|* See 'llvm/lib/Support/BLAKE3/LICENSE' for info.                            *|
|* SPDX-License-Identifier: CC0-1.0                                           *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This header declares the C interface to LLVM's BLAKE3 implementation.      *|
|* Original BLAKE3 C API: https://github.com/BLAKE3-team/BLAKE3/tree/1.3.1/c  *|
|*                                                                            *|
|* Symbols are prefixed with 'llvm' to avoid a potential conflict with        *|
|* another BLAKE3 version within the same program.                            *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

module llvm.c.blake3d;

extern(C) nothrow:

enum LLVM_BLAKE3_VERSION_STRING = "1.3.1";
enum LLVM_BLAKE3_KEY_LEN = 32;
enum LLVM_BLAKE3_OUT_LEN = 32;
enum LLVM_BLAKE3_BLOCK_LEN = 64;
enum LLVM_BLAKE3_CHUNK_LEN = 1024;
enum LLVM_BLAKE3_MAX_DEPTH = 54;

// This struct is a private implementation detail. It has to be here because
// it's part of llvm_blake3_hasher below.
struct llvm_blake3_chunk_state {
  uint[8] cv;
  ulong chunk_counter;
  ubyte[LLVM_BLAKE3_BLOCK_LEN] buf;
  ubyte buf_len;
  ubyte blocks_compressed;
  ubyte flags;
}

struct llvm_blake3_hasher {
  uint[8] key;
  llvm_blake3_chunk_state chunk;
  ubyte cv_stack_len;
  // The stack size is MAX_DEPTH + 1 because we do lazy merging. For example,
  // with 7 chunks, we have 3 entries in the stack. Adding an 8th chunk
  // requires a 4th entry, rather than merging everything down to 1, because we
  // don't know whether more input is coming. This is different from how the
  // reference implementation does things.
  ubyte[(LLVM_BLAKE3_MAX_DEPTH + 1) * LLVM_BLAKE3_OUT_LEN] cv_stack;
}

const(char)* llvm_blake3_version();
void llvm_blake3_hasher_init(llvm_blake3_hasher* self);
void llvm_blake3_hasher_init_keyed(llvm_blake3_hasher* self,
                                   const ubyte[LLVM_BLAKE3_KEY_LEN] key);
void llvm_blake3_hasher_init_derive_key(llvm_blake3_hasher* self,
                                        const(char)* context);
void llvm_blake3_hasher_init_derive_key_raw(llvm_blake3_hasher* self,
                                            const(void)* context,
                                            size_t context_len);
void llvm_blake3_hasher_update(llvm_blake3_hasher* self, const(void)* input,
                               size_t input_len);
void llvm_blake3_hasher_finalize(const llvm_blake3_hasher* self, ubyte* out,
                                 size_t out_len);
void llvm_blake3_hasher_finalize_seek(const llvm_blake3_hasher* self,
                                      uint64_t seek, ubyte* out,
                                      size_t out_len);
void llvm_blake3_hasher_reset(llvm_blake3_hasher* self);
