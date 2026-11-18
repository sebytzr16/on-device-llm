import '../../core/l10n/l10n.dart';
import 'mcp_config.dart';

String mcpExplain(AppLocalizations t, Object error) {
  if (error is! McpException) return t.mcpOtherError('$error');
  return switch (error.problem) {
    McpProblem.config => switch (error.detail) {
      'name' => t.mcpNameTakenError,
      'args' => t.mcpArgsError,
      'env' => t.mcpEnvError,
      'command' => t.mcpCommandError,
      _ => t.mcpConfigError,
    },
    McpProblem.loopback => t.mcpLoopbackError,
    McpProblem.protocol => t.mcpProtocolError,
    McpProblem.closed => t.mcpClosedError,
    McpProblem.timeout => t.mcpTimeoutError,
    McpProblem.unavailable => t.mcpUnavailableError,
    McpProblem.denied => t.mcpDeniedError,
    McpProblem.batchArgs => t.mcpBatchArgsError,
  };
}
