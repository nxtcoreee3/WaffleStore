#!/usr/bin/env python3
"""Apply experimental TCI adaptation to a checksum-pinned Unicorn 2.1.4 tree.

Downloaded QEMU files keep their GPL headers. This is not a production SAP
interpreter; the synthetic CPU/hook probe is deliberately separate from SAP.
"""
import hashlib
import pathlib
import sys
import urllib.request

root = pathlib.Path(sys.argv[1])
files = {
    'tcg/tci.c': '35796a4f3ee883fdfb7ea25ced049544bf87fa1c42c6c4f99f2cf179d0a1bb39',
    'tcg/tci/tcg-target.h': '9440020dbbef4b25dbfc8e6aef4fd1e6b6fbe301994af432bafe7da579fb5638',
    'tcg/tci/tcg-target.inc.c': '4c63d656f87b8a15f2b7828b24530c0b5f31f9d6fde932e4a6364a4a666296eb',
}
for name, digest in files.items():
    data = urllib.request.urlopen('https://raw.githubusercontent.com/qemu/qemu/v5.0.0/' + name, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError('QEMU TCI source integrity mismatch: ' + name)
    path = root / 'qemu' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)

def replace(name, old, new, count=1):
    path = root / name
    text = path.read_text()
    if text.count(old) != count:
        raise RuntimeError('Unexpected Unicorn source layout: ' + name + ': ' + old)
    path.write_text(text.replace(old, new))

replace('CMakeLists.txt', 'add_compile_options(\n        ${UNICORN_CFLAGS}',
        'set(UNICORN_TARGET_ARCH "tci")\n    add_compile_options(\n        -DCONFIG_TCG_INTERPRETER\n        ${UNICORN_CFLAGS}')
replace('CMakeLists.txt', '    qemu/tcg/tcg.c\n', '    qemu/tcg/tcg.c\n    qemu/tcg/tci.c\n')
replace('qemu/tcg/tci/tcg-target.inc.c', 'tcg_op_defs_max', 'NB_OPS')
replace('qemu/tcg/tci/tcg-target.inc.c', 'tcg_target_available_regs[', 's->tcg_target_available_regs[', 2)
replace('qemu/tcg/tci/tcg-target.inc.c', 'tcg_target_call_clobber_regs =', 's->tcg_target_call_clobber_regs =')
# The old QEMU interpreter used a process-global helper PC. Unicorn supports
# multiple instances; use TLS to avoid sharing it between threads. Nested calls
# on one thread remain a validation item for full SAP hooks.
replace('qemu/include/exec/exec-all.h', '#ifdef _MSC_VER\n#include <intrin.h>',
        '#if defined(CONFIG_TCG_INTERPRETER)\nextern __thread uintptr_t tci_tb_ptr;\n# define GETPC() tci_tb_ptr\n#elif defined(_MSC_VER)\n#include <intrin.h>')
replace('qemu/tcg/tci.c', '#include "exec/cpu_ldst.h"',
        '#include "exec/cpu_ldst.h"\n#include "exec/exec-all.h"\n__thread uintptr_t tci_tb_ptr;')
# Bytecode buffers are data, even when the guest memory permissions say RX.
replace('qemu/accel/tcg/translate-all.c', 'int prot = PROT_WRITE | PROT_READ | PROT_EXEC;',
        'int prot = PROT_WRITE | PROT_READ;')
replace('qemu/accel/tcg/translate-all.c', '#ifdef USE_MAP_JIT',
        '#if defined(USE_MAP_JIT) && !defined(CONFIG_TCG_INTERPRETER)')
replace('qemu/accel/tcg/translate-all.c', '    if (qemu_mprotect_rwx(buf, size)) {\n        abort();\n    }',
        '#if !defined(CONFIG_TCG_INTERPRETER)\n    if (qemu_mprotect_rwx(buf, size)) {\n        abort();\n    }\n#endif')
for name in ['qemu/include/tcg/tcg-apple-jit.h', 'qemu/accel/tcg/translate-all.c', 'uc.c']:
    path = root / name
    text = path.read_text()
    text = text.replace('defined(__APPLE__) && defined(HAVE_PTHREAD_JIT_PROTECT)',
                        '!defined(CONFIG_TCG_INTERPRETER) && defined(__APPLE__) && defined(HAVE_PTHREAD_JIT_PROTECT)')
    text = text.replace('#ifdef HAVE_PTHREAD_JIT_PROTECT',
                        '#if defined(HAVE_PTHREAD_JIT_PROTECT) && !defined(CONFIG_TCG_INTERPRETER)')
    path.write_text(text)
print('Prepared experimental Unicorn 2.1.4 + checksum-pinned QEMU 5.0 TCI (no host executable bytecode).')
