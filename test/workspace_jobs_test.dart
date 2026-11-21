import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/workspace_jobs.dart';

void main() {
  test(
    'a paused subscriber receives completion emitted during replay',
    () async {
      final job = WorkspaceJob('job', 'request', 'input');
      addTearDown(job.dispose);
      job.emit('started');
      job.emit('agent', {'id': 'a', 'output': 'working'});
      final subscriber = StreamIterator(job.events(compact: true));
      addTearDown(subscriber.cancel);
      expect(await subscriber.moveNext(), isTrue);
      job.emit('agent', {'id': 'a', 'output': 'finished'});
      job.emit('done');
      final remaining = <Map<String, dynamic>>[];
      while (await subscriber.moveNext()) {
        remaining.add(subscriber.current);
      }
      expect(remaining.last['type'], 'done');
      expect(
        remaining
            .where((event) => event['type'] == 'agent')
            .last['data']['output'],
        'finished',
      );
    },
  );

  test('a large replacement snapshot is not charged twice', () async {
    final job = WorkspaceJob('job', 'request', 'input');
    addTearDown(job.dispose);
    final output = 'x' * (WorkspaceJob.maxJournalBytes ~/ 2 + 1000);
    job.emit('agent', {'id': 'a', 'output': output});
    job.emit('agent', {'id': 'a', 'output': '$output updated'});
    expect(job.cancel.isCancelled, isFalse);
    expect(job.retainedBytes, lessThan(WorkspaceJob.maxJournalBytes));
    job.emit('done');
    final snapshots = (await job.events(compact: true).toList()).where(
      (event) => event['type'] == 'agent',
    );
    expect(snapshots.single['data']['output'], endsWith(' updated'));
  });

  test(
    'four streaming snapshots compact without cancelling long jobs',
    () async {
      final job = WorkspaceJob('job', 'request', 'input');
      addTearDown(job.dispose);
      job.emit('started');
      for (var step = 0; step < 500; step++) {
        for (var agent = 0; agent < 4; agent++) {
          job.emit('agent', {
            'id': 'a$agent',
            'phase': 'generating',
            'output': '${'writing ' * 1200}$step:$agent',
            'elapsedMs': step * 200,
          });
        }
      }
      expect(job.cancel.isCancelled, isFalse);
      expect(job.terminal, isFalse);
      expect(
        job.retainedBytes,
        lessThanOrEqualTo(WorkspaceJob.maxJournalBytes),
      );
      job.emit('done');
      final replay = await job.events(compact: true).toList();
      expect(replay.any((event) => event['type'] == 'checkpoint'), isTrue);
      for (var agent = 0; agent < 4; agent++) {
        final latest = replay
            .where(
              (event) =>
                  event['type'] == 'agent' && event['data']['id'] == 'a$agent',
            )
            .last;
        expect(latest['data']['output'], endsWith('499:$agent'));
      }
      final legacy = await job.events().toList();
      expect(
        legacy.map((event) => event['sequence']),
        List.generate(job.sequence, (index) => index + 1),
      );
      final resumed = await job.events(after: 1000, compact: true).toList();
      expect(resumed.first['sequence'], 1001);
      expect(resumed.last['type'], 'done');
    },
  );

  test(
    'rejoining replays ordered activity without duplicating execution',
    () async {
      final jobs = WorkspaceJobs();
      addTearDown(jobs.dispose);
      final finish = Completer<void>();
      var runs = 0;
      final job = jobs.submit(
        requestId: 'phone-1',
        fingerprint: 'same',
        run: (job) async {
          runs++;
          job.emit('agent', {'id': 'agent-1', 'output': 'working'});
          await finish.future;
          job.emit('text', {'text': 'finished'});
        },
      );
      final first = await job.events().take(2).toList();
      expect(first.map((e) => e['sequence']), [1, 2]);
      expect(
        jobs.submit(
          requestId: 'phone-1',
          fingerprint: 'same',
          run: (_) async {
            fail('must not run twice');
          },
        ),
        same(job),
      );
      finish.complete();
      final rest = await job.events(after: 2).toList();
      expect(rest.map((e) => e['type']), ['text', 'done']);
      expect(runs, 1);
    },
  );

  test('request IDs cannot be reused for different input', () async {
    final jobs = WorkspaceJobs();
    addTearDown(jobs.dispose);
    jobs.submit(requestId: 'id', fingerprint: 'a', run: (_) async {});
    expect(
      () => jobs.submit(requestId: 'id', fingerprint: 'b', run: (_) async {}),
      throwsStateError,
    );
  });

  test(
    'approval waits for decision and stop releases pending approvals',
    () async {
      final job = WorkspaceJob('job', 'request', 'input');
      addTearDown(job.dispose);
      final approval = job.approve('Allow server web access?');
      final event = await job.events().first;
      expect(event['type'], 'approval');
      expect(job.decide(event['data']['id'] as String, true), isTrue);
      expect(await approval, isTrue);
      final pending = job.approve('Another action?');
      job.stop();
      expect(await pending, isFalse);
      expect(job.cancel.isCancelled, isTrue);
      expect((await job.events().toList()).last['type'], 'cancelled');
    },
  );

  test('full queue refuses new work but retains idempotent requests', () async {
    final jobs = WorkspaceJobs(maxActive: 1);
    addTearDown(jobs.dispose);
    final finish = Completer<void>();
    final first = jobs.submit(
      requestId: '1',
      fingerprint: 'a',
      run: (_) => finish.future,
    );
    expect(
      () => jobs.submit(requestId: '2', fingerprint: 'b', run: (_) async {}),
      throwsStateError,
    );
    expect(
      jobs.submit(requestId: '1', fingerprint: 'a', run: (_) async {}),
      same(first),
    );
    finish.complete();
  });

  test('event retention overflow cancels once without recursion', () async {
    final job = WorkspaceJob('job', 'request', 'input');
    addTearDown(job.dispose);
    job.emit('text', {'text': 'x' * WorkspaceJob.maxJournalBytes});
    expect(job.terminal, isTrue);
    expect(job.cancel.isCancelled, isTrue);
    expect((await job.events().toList()).single['type'], 'cancelled');
  });

  for (final terminal in ['done', 'failed', 'cancelled']) {
    test('a full journal still replays a bounded $terminal event', () async {
      const budget = 320;
      final jobs = WorkspaceJobs(maxActive: 1, maxRetainedBytes: budget);
      addTearDown(jobs.dispose);
      final job = jobs.submit(
        requestId: terminal,
        fingerprint: terminal,
        run: (job) async {
          job.emit('text', {'text': 'x' * 20});
          expect(job.terminal, isFalse);
          job.emit(terminal, {'reason': 'x' * budget});
        },
      );
      await job.execution;
      final events = await job.events().toList();
      expect(events.map((event) => event['type']), [
        'queued',
        'text',
        terminal,
      ]);
      expect(events.last['data'], isEmpty);
      expect(job.terminal, isTrue);
      expect(jobs.retainedBytes, job.retainedBytes);
      expect(jobs.retainedBytes, lessThanOrEqualTo(budget));
    });
  }

  test('retained journals share one byte budget', () async {
    const budget = 8000;
    final jobs = WorkspaceJobs(maxActive: 1, maxRetainedBytes: budget);
    addTearDown(jobs.dispose);
    Future<WorkspaceJob> finish(String requestId) async {
      final job = jobs.submit(
        requestId: requestId,
        fingerprint: requestId,
        run: (job) async {
          job.emit('text', {'text': 'x' * 6000});
          job.emit('done');
        },
      );
      await job.execution;
      expect(jobs.retainedBytes, lessThanOrEqualTo(budget));
      return job;
    }

    final first = await finish('1');
    final second = await finish('2');
    // The total is enforced on every append, not on admission: the oldest
    // terminal journal makes room instead of both being retained.
    expect(jobs[first.id], isNull);
    expect(jobs[second.id], isNotNull);
    final third = await finish('3');
    expect(jobs[third.id], isNotNull);
    expect(jobs.retainedBytes, lessThanOrEqualTo(budget));
  });

  test('concurrent journals stay inside the aggregate budget', () async {
    const budget = 20000;
    final jobs = WorkspaceJobs(maxActive: 3, maxRetainedBytes: budget);
    addTearDown(jobs.dispose);
    // Fill most of the budget with finished journals first.
    for (var i = 0; i < 3; i++) {
      final old = jobs.submit(
        requestId: 'old$i',
        fingerprint: 'old$i',
        run: (job) async {
          job.emit('text', {'text': 'x' * 6000});
          job.emit('done');
        },
      );
      await old.execution;
      expect(jobs.retainedBytes, lessThanOrEqualTo(budget));
    }
    final started = <WorkspaceJob>[];
    for (var i = 0; i < 3; i++) {
      started.add(
        jobs.submit(
          requestId: 'new$i',
          fingerprint: 'new$i',
          run: (job) async {
            for (var n = 0; n < 10 && !job.terminal; n++) {
              job.emit('text', {'text': 'x' * 3000});
              await Future<void>.delayed(Duration.zero);
              expect(jobs.retainedBytes, lessThanOrEqualTo(budget));
            }
            job.emit('done');
          },
        ),
      );
      expect(jobs.retainedBytes, lessThanOrEqualTo(budget));
    }
    await Future.wait([for (final job in started) job.execution]);
    // Whatever each job did, the shared budget, not the job count, caps it.
    expect(jobs.retainedBytes, lessThanOrEqualTo(budget));
    expect(jobs.retainedBytes, greaterThan(0));
  });
}
