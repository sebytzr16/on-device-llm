// Serial acceptance checks sharing one installed test build and model.
import 'abi6_drill_test.dart' as abi;
import 'document_export_device_test.dart' as documents;
import 'native_bench_test.dart' as benchmark;

void main() {
  abi.main();
  documents.main();
  benchmark.main();
}
