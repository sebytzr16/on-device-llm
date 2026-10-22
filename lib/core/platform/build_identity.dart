/// Release scripts inject the actual worktree identity. An ordinary
/// development build explicitly says its source was not recorded.
abstract final class BuildIdentity {
  static const version = String.fromEnvironment(
    'ODLLM_VERSION',
    defaultValue: '0.1.1+2',
  );
  static const source = String.fromEnvironment(
    'ODLLM_SOURCE',
    defaultValue: 'development (unrecorded)',
  );
  static const native = String.fromEnvironment(
    'ODLLM_NATIVE',
    defaultValue: 'unrecorded',
  );
  static const abi = 7;
  static Map<String, Object> toJson() => {
    'version': version,
    'source': source,
    'nativeRevision': native,
    'nativeAbi': abi,
  };
}
