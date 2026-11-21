import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/presentation/hosted_workspace.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
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

  test('host knowledge is available only to local jobs with permission', () {
    const host = InferenceSettings(toolDocuments: true, remoteDocuments: true);
    const overrides = {'toolDocuments': true, 'remoteDocuments': true};
    expect(hostedWorkspaceSettings(host, overrides).toolDocuments, isFalse);
    expect(hostedWorkspaceSettings(host, null).toolDocuments, isFalse);
    expect(
      hostedWorkspaceSettings(
        host.copyWith(remoteDocuments: false),
        overrides,
        principal: 'local',
      ).toolDocuments,
      isTrue,
    );
    expect(
      hostedWorkspaceSettings(
        host.copyWith(toolDocuments: false),
        overrides,
        principal: 'local',
      ).toolDocuments,
      isFalse,
    );
    expect(
      hostedWorkspaceSettings(host, const {
        'toolDocuments': false,
      }, principal: 'local').toolDocuments,
      isFalse,
    );
  });

  test('host documents are advertised only to the local principal', () {
    final api = WorkspaceApi(
      capabilities: workspaceCapabilities,
      localCapabilities: workspaceLocalCapabilities,
      run: (_, _) async {},
    );
    expect(api.capabilitiesFor('local'), contains('documents'));
    expect(api.capabilitiesFor('local'), containsAll(workspaceCapabilities));
    expect(api.capabilitiesFor('paired-device'), isNot(contains('documents')));
    expect(api.capabilitiesFor('paired-device'), workspaceCapabilities);
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

  test('paired jobs get host documents only with the sharing switch', () {
    const withoutSwitch = InferenceSettings(toolDocuments: true);
    const withSwitch = InferenceSettings(
      toolDocuments: true,
      hostShareDocuments: true,
    );
    const ask = {'toolDocuments': true};
    // Without the switch a paired job never gets the collection.
    expect(
      hostedWorkspaceSettings(
        withoutSwitch,
        ask,
        principal: 'paired-device',
      ).toolDocuments,
      isFalse,
    );
    expect(
      hostedWorkspaceSettings(
        withoutSwitch,
        null,
        principal: 'paired-device',
      ).toolDocuments,
      isFalse,
    );
    // With the switch and the host's document tool on, it does.
    expect(
      hostedWorkspaceSettings(
        withSwitch,
        ask,
        principal: 'paired-device',
      ).toolDocuments,
      isTrue,
    );
    expect(
      hostedWorkspaceSettings(
        withSwitch,
        null,
        principal: 'paired-device',
      ).toolDocuments,
      isTrue,
    );
    // The switch alone does not bypass the host's own document tool.
    expect(
      hostedWorkspaceSettings(
        withSwitch.copyWith(toolDocuments: false),
        ask,
        principal: 'paired-device',
      ).toolDocuments,
      isFalse,
    );
    // A paired client may still narrow it, and loopback keeps its access.
    expect(
      hostedWorkspaceSettings(withSwitch, const {
        'toolDocuments': false,
      }, principal: 'paired-device').toolDocuments,
      isFalse,
    );
    expect(
      hostedWorkspaceSettings(
        withoutSwitch,
        ask,
        principal: 'local',
      ).toolDocuments,
      isTrue,
    );
  });

  test('the legacy shared token never gets host documents', () {
    const host = InferenceSettings(
      toolDocuments: true,
      hostShareDocuments: true,
    );
    const ask = {'toolDocuments': true};
    expect(
      hostedWorkspaceSettings(host, ask, principal: 'legacy').toolDocuments,
      isFalse,
    );
    expect(
      hostedWorkspaceSettings(host, null, principal: 'legacy').toolDocuments,
      isFalse,
    );
    final api = WorkspaceApi(
      capabilities: workspaceCapabilities,
      localCapabilities: workspaceLocalCapabilities,
      shareDocuments: () => true,
      run: (_, _) async {},
    );
    expect(api.capabilitiesFor('legacy'), isNot(contains('documents')));
    expect(api.capabilitiesFor('legacy'), workspaceCapabilities);
    expect(api.capabilitiesFor('paired-device'), contains('documents'));
    expect(api.capabilitiesFor('local'), contains('documents'));
  });

  test('a workspace client cannot turn document sharing on', () {
    const host = InferenceSettings(
      toolDocuments: true,
      hostShareDocuments: false,
    );
    final settings = hostedWorkspaceSettings(host, const {
      'hostShareDocuments': true,
      'toolDocuments': true,
    });
    expect(settings.hostShareDocuments, isFalse);
    expect(settings.toolDocuments, isFalse);
    // The host owner's value survives a client that tries to clear it.
    final shared = hostedWorkspaceSettings(
      host.copyWith(hostShareDocuments: true),
      const {'hostShareDocuments': false},
    );
    expect(shared.hostShareDocuments, isTrue);
  });

  test('documents capability follows the sharing switch', () {
    var share = false;
    final api = WorkspaceApi(
      capabilities: workspaceCapabilities,
      localCapabilities: workspaceLocalCapabilities,
      shareDocuments: () => share,
      run: (_, _) async {},
    );
    expect(api.capabilitiesFor('local'), contains('documents'));
    expect(api.capabilitiesFor('paired-device'), isNot(contains('documents')));
    expect(api.capabilitiesFor('paired-device'), workspaceCapabilities);
    share = true;
    expect(api.capabilitiesFor('paired-device'), contains('documents'));
    expect(
      api.capabilitiesFor('paired-device'),
      containsAll(workspaceCapabilities),
    );
  });
}
