import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

const _s25 = '''
processor	: 0
BogoMIPS	: 38.40
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 sve asimdfhm dit uscat ilrcpc flagm ssbs sb paca pacg dcpodp sve2 sveaes svepmull svebitperm svesha3 svesm4 flagm2 frint svei8mm svebf16 i8mm bf16 dgh bti
CPU implementer	: 0x51

processor	: 1
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 sve asimdfhm dit uscat ilrcpc flagm ssbs sb paca pacg dcpodp sve2 sveaes svepmull svebitperm svesha3 svesm4 flagm2 frint svei8mm svebf16 i8mm bf16 dgh bti
CPU implementer	: 0x51
''';

const _sd865 = '''
processor	: 0
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp
CPU implementer	: 0x51
''';

const _x86Avx2 = '''
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 85
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand hypervisor lahf_lm abm 3dnowprefetch fsgsbase bmi1 hle avx2 smep bmi2 erms invpcid rtm mpx avx512f
processor	: 1
vendor_id	: GenuineIntel
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand hypervisor lahf_lm abm 3dnowprefetch fsgsbase bmi1 hle avx2 smep bmi2 erms invpcid rtm mpx avx512f
''';

const _x86Nehalem = '''
processor	: 0
vendor_id	: GenuineIntel
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx rdtscp lm constant_tsc nonstop_tsc sse4_2 popcnt
processor	: 1
vendor_id	: GenuineIntel
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx rdtscp lm constant_tsc nonstop_tsc sse4_2 popcnt
''';

void main() {
  test('fast arm64 variant only when every core lists i8mm', () {
    expect(LlamaBindings.cpuHasI8mm(cpuinfo: _s25), isTrue);
    expect(LlamaBindings.cpuHasI8mm(cpuinfo: _sd865), isFalse);
    // A mixed cluster (one core without i8mm) must not load the fast library.
    expect(LlamaBindings.cpuHasI8mm(cpuinfo: _s25 + _sd865), isFalse);
    // "svei8mm" alone is not "i8mm".
    expect(
      LlamaBindings.cpuHasI8mm(cpuinfo: 'Features\t: fp asimd svei8mm\n'),
      isFalse,
    );
    expect(LlamaBindings.cpuHasI8mm(cpuinfo: ''), isFalse);
  });

  test('fast x86_64 variant only when every core lists avx2', () {
    expect(LlamaBindings.cpuHasAvx2(cpuinfo: _x86Avx2), isTrue);
    expect(LlamaBindings.cpuHasAvx2(cpuinfo: _x86Nehalem), isFalse);
    // A VM that exposes avx2 on one core only must not load the fast library.
    expect(LlamaBindings.cpuHasAvx2(cpuinfo: _x86Avx2 + _x86Nehalem), isFalse);
    expect(LlamaBindings.cpuHasAvx2(cpuinfo: ''), isFalse);
  });

  test('an arm64 CPU never satisfies the x86_64 check and vice versa', () {
    expect(LlamaBindings.cpuHasAvx2(cpuinfo: _s25), isFalse);
    expect(LlamaBindings.cpuHasI8mm(cpuinfo: _x86Avx2), isFalse);
  });

  test('fast CPU kernels remain available without the OpenCL variant', () {
    expect(LlamaBindings.androidVariants, [
      'libondevice_llm_opencl.so',
      'libondevice_llm_cpu_avx2.so',
      'libondevice_llm_cpu_i8mm.so',
      'libondevice_llm.so',
    ]);
    final cpuOnly = LlamaBindings.androidVariants.where(
      (name) => !name.contains('opencl'),
    );
    expect(cpuOnly.first, 'libondevice_llm_cpu_avx2.so');
    expect(cpuOnly.elementAt(1), 'libondevice_llm_cpu_i8mm.so');
    expect(cpuOnly.last, 'libondevice_llm.so');
  });

  test('both optimized libraries are skipped on older or mixed CPUs', () {
    for (final cpuinfo in [_sd865, _s25 + _sd865, '']) {
      final eligible = LlamaBindings.androidVariants.where(
        (name) =>
            (!LlamaBindings.variantNeedsI8mm(name) ||
                LlamaBindings.cpuHasI8mm(cpuinfo: cpuinfo)) &&
            (!LlamaBindings.variantNeedsAvx2(name) ||
                LlamaBindings.cpuHasAvx2(cpuinfo: cpuinfo)),
      );
      expect(eligible, ['libondevice_llm.so']);
    }
  });

  test('x86_64 gets the AVX2 bridge and skips the arm64-only ones', () {
    final eligible = LlamaBindings.androidVariants.where(
      (name) =>
          (!LlamaBindings.variantNeedsI8mm(name) ||
              LlamaBindings.cpuHasI8mm(cpuinfo: _x86Avx2)) &&
          (!LlamaBindings.variantNeedsAvx2(name) ||
              LlamaBindings.cpuHasAvx2(cpuinfo: _x86Avx2)),
    );
    expect(eligible, ['libondevice_llm_cpu_avx2.so', 'libondevice_llm.so']);
  });
}
