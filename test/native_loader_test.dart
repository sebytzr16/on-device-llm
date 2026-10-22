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

void main() {
  test('fast variant only when every core lists i8mm', () {
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

  test('fast CPU kernels remain available without the OpenCL variant', () {
    expect(LlamaBindings.androidVariants, [
      'libondevice_llm_opencl.so',
      'libondevice_llm_cpu_i8mm.so',
      'libondevice_llm.so',
    ]);
    final cpuOnly = LlamaBindings.androidVariants.where(
      (name) => !name.contains('opencl'),
    );
    expect(cpuOnly.first, 'libondevice_llm_cpu_i8mm.so');
  });

  test('both optimized libraries are skipped on older or mixed CPUs', () {
    for (final cpuinfo in [_sd865, _s25 + _sd865, '']) {
      final eligible = LlamaBindings.androidVariants.where(
        (name) =>
            !LlamaBindings.variantNeedsI8mm(name) ||
            LlamaBindings.cpuHasI8mm(cpuinfo: cpuinfo),
      );
      expect(eligible, ['libondevice_llm.so']);
    }
  });
}
