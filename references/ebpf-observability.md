---
description: In-depth technical architecture of eBPF observability, kprobes, fentry, uprobes, TLS extraction, Beyla, and Linux capabilities.
metadata:
  tags: [ebpf, beyla, kprobes, uprobes, fentry, tls, capabilities, co-re]
---

# eBPF (Extended Berkeley Packet Filter) Observability

eBPF enables sandboxed, high-performance programs to run directly within the Linux kernel upon system events, enabling zero-code telemetry extraction without modifying application binaries or injecting bytecode agents.

---

## 1. Kernel vs. User-Space Probes

```
+-------------------------------------------------------------------------+
| USER SPACE                                                              |
|                                                                         |
|  [ Application Process ] ---> [ libssl.so / BoringSSL ]                 |
|                                       |                                 |
|                                       v (uprobe / uretprobe)            |
+-------------------------------------------------------------------------+
| LINUX KERNEL SPACE                                                      |
|                                                                         |
|  [ Syscall Layer ]       ---> (tracepoints: sys_enter_write/read)       |
|  [ Virtual Filesystem ]  ---> (kprobe / fentry: vfs_write)              |
|  [ TCP / IP Stack ]      ---> (fentry / fexit: tcp_v4_connect)          |
|  [ Socket Layer ]        ---> (BPF sockops: BPF_SOCK_OPS_STATE_CB)      |
|  [ Network Device / TC ] ---> (BPF Traffic Control clsact)              |
|                                                                         |
|                 +-----------------------------------+                   |
|                 | BPF Ring Buffer (Lockless SPSC)   |                   |
|                 +-----------------------------------+                   |
+-----------------------------------|-------------------------------------+
                                    | epoll / ring_buffer__poll()
                                    v
+-------------------------------------------------------------------------+
| AGENT SPACE (Grafana Beyla / OTel eBPF Profiler)                        |
|                                                                         |
|  - Reads plaintext spans from ring buffer                               |
|  - Enriches with Kubernetes Pod, Namespace, and Node metadata via /proc |
|  - Exports OTLP Traces & Metrics to Collector                           |
+-------------------------------------------------------------------------+
```

### 1.1 Probe Characteristics

| Probe Type | Invocation Mechanism | Latency Overhead | Kernel Stability | Primary Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **`fentry` / `fexit`** | Direct BPF trampoline call | ~5–15 ns | Unstable (tracks kernel signatures) | TCP connection tracking, socket lifecycle |
| **`tracepoint`** | Static kernel trace macro | ~10–25 ns | **Stable** (Guaranteed Linux ABI) | Syscall monitoring (`sys_enter_write`) |
| **`kprobe` / `kretprobe`**| Kernel dynamic breakpoint | ~70–120 ns | Unstable | Hooking non-exported kernel routines |
| **`uprobe` / `uretprobe`**| User-space memory breakpoint (`int3`) | ~1.5–3.5 μs | Application dependent | TLS interception (`SSL_write`/`SSL_read`) |
| **`sockops`** | Triggered on TCP state changes | ~15–30 ns | **Stable** | Measuring TCP round-trip time (RTT) |
| **`TC` (Traffic Control)**| Network queueing disciplines | ~20–40 ns | **Stable** | Raw packet inspection and L7 parsing |

---

## 2. TLS Uprobes for Encrypted Traffic

Because TLS encrypts application traffic before it reaches kernel sockets, network packet sniffers cannot inspect HTTP methods, status codes, or W3C `traceparent` headers. Auto-instrumentation overcomes this by attaching uprobes to cryptographic libraries:

1. **OpenSSL / BoringSSL**:
   - Hook `SSL_write(SSL *ssl, const void *buf, int num)` on entry: Extract plaintext payload and headers before encryption.
   - Hook `SSL_read(SSL *ssl, void *buf, int num)` on return: Extract plaintext response after decryption.
   - Pointer offset resolution: The underlying file descriptor is retrieved by navigating `ssl->wbio->num`.
2. **Go `crypto/tls`**:
   - Go compiles statically without `libssl.so`.
   - Beyla attaches to `crypto/tls.(*Conn).Write` and `Read`.
   - On Go 1.17+, the Go ABI uses register-based parameter passing (`RAX`, `RBX`), which the eBPF probe reads dynamically based on architecture.

---

## 3. CO-RE (Compile Once - Run Everywhere) & BTF

Historically, compiling eBPF programs required installing Clang, LLVM, and kernel headers directly on production nodes. Modern eBPF relies on **CO-RE**:
1. **`vmlinux.h`**: A single C header dumped from `/sys/kernel/btf/vmlinux` containing all kernel structs.
2. **Clang Annotations**: eBPF source uses `BPF_CORE_READ()` to preserve member access offsets.
3. **BTF (BPF Type Format)**: Embedded kernel metadata describing struct layouts on the target host.
4. **`libbpf` Relocation**: At load time, `libbpf` compares the compiled offset against the target host kernel BTF and dynamically rewrites byte offsets before program verification.

---

## 4. Capability Sandboxing (Linux 5.8+)

Do not run eBPF agents as fully privileged `root` with `privileged: true`. Modern Linux kernels support fine-grained capabilities:
- **`CAP_BPF`**: Load eBPF programs and create maps.
- **`CAP_PERFMON`**: Attach kprobes, uprobes, and tracepoints.
- **`CAP_NET_ADMIN`**: Attach TC and sockops filters.
- **`CAP_SYS_PTRACE`**: Inspect container process namespaces via `/proc/<pid>`.
