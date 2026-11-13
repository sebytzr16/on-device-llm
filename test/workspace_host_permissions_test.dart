import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/presentation/hosted_workspace.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  test('a workspace client cannot raise host tool and web permissions', () {
    const host = InferenceSettings(
      toolsEnabled: false,
      toolWeb: false,
      toolCalculator: false,
      toolDocuments: false,
      toolActions: false,
      toolHelper: false,
      webMode: WebMode.off,
      agentWebAccess: AgentWebAccess.never,
    );
    final settings = hostedWorkspaceSettings(host, {
      'toolsEnabled': true,
      'toolWeb': true,
      'toolCalculator': true,
      'toolDocuments': true,
      'toolActions': true,
      'toolHelper': true,
      'webMode': 'always',
      'webSearchEnabled': true,
      'agentWebAccess': 'alwaysAllow',
      'agentNewPermission': true,
    });
    expect(settings.toolsEnabled, false);
    expect(settings.toolWeb, false);
    expect(settings.toolCalculator, false);
    expect(settings.toolDocuments, false);
    expect(settings.toolActions, false);
    expect(settings.toolHelper, false);
    expect(settings.webMode, WebMode.off);
    expect(settings.agentWebAccess, AgentWebAccess.never);
  });

  test('a workspace client can narrow host permissions', () {
    const host = InferenceSettings(
      toolsEnabled: true,
      toolWeb: true,
      toolCalculator: true,
      toolDocuments: true,
      toolActions: true,
      toolHelper: true,
      webMode: WebMode.always,
      agentWebAccess: AgentWebAccess.alwaysAllow,
    );
    final settings = hostedWorkspaceSettings(host, {
      'toolsEnabled': false,
      'toolWeb': false,
      'toolCalculator': false,
      'toolDocuments': false,
      'toolActions': false,
      'toolHelper': false,
      'webMode': 'off',
      'agentWebAccess': 'never',
      'agentTemperature': 0.2,
    });
    expect(settings.toolsEnabled, false);
    expect(settings.toolWeb, false);
    expect(settings.toolCalculator, false);
    expect(settings.toolDocuments, false);
    expect(settings.toolActions, false);
    expect(settings.toolHelper, false);
    expect(settings.webMode, WebMode.off);
    expect(settings.agentWebAccess, AgentWebAccess.never);
    expect(settings.agentTemperature, 0.2);
  });

  test('only known non-permission agent settings are accepted', () {
    const host = InferenceSettings(
      webMode: WebMode.auto,
      agentWebAccess: AgentWebAccess.askOnce,
    );
    final settings = hostedWorkspaceSettings(host, {
      'agentWebAccess': 'alwaysAllow',
      'agentTemperature': 0.1,
      'agentFutureNetworkTool': true,
    });
    expect(settings.agentWebAccess, AgentWebAccess.askOnce);
    expect(settings.agentTemperature, 0.1);
    expect(settings.toJson().containsKey('agentFutureNetworkTool'), false);
  });
}
