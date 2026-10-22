// One serial device build for vendor access, native GPU operations and the
// measured CPU/OpenCL comparison. Run test-android.ps1 with -Backend opencl,
// -Model <GGUF> and a fixed -Threads value matching the CPU benchmark.
import 'native_bench_test.dart' as benchmark;
import 'native_smoke_test.dart' as smoke;
import 'opencl_probe_test.dart' as driver;

void main() {
  driver.main();
  smoke.main();
  benchmark.main();
}
