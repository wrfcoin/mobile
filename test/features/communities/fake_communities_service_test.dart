import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/communities/data/fake/fake_communities_service.dart';
import 'package:wrfcoin_mobile/features/communities/data/models/cluster_model.dart';

void main() {
  late FakeCommunitiesService svc;

  setUp(() => svc = FakeCommunitiesService());

  // ── Discovery ──────────────────────────────────────────────────────────────

  test('getNearbyClusters seeds fixture clusters on first call', () async {
    final result = await svc.getNearbyClusters(userId: 'u1');
    final clusters = result.getRight().toNullable()!;
    expect(clusters.length, greaterThanOrEqualTo(2));
    expect(clusters.any((c) => c.name == 'Fog Belt Monitors'), isTrue);
    expect(clusters.any((c) => c.name == 'Delta Weather Watch'), isTrue);
  });

  test('getNearbyClusters returns same list on subsequent calls', () async {
    final first = (await svc.getNearbyClusters(userId: 'u1')).getRight().toNullable()!;
    final second = (await svc.getNearbyClusters(userId: 'u1')).getRight().toNullable()!;
    expect(first.length, second.length);
  });

  // ── Membership ────────────────────────────────────────────────────────────

  test('joinByInviteCode adds user to cluster', () async {
    final result = await svc.joinByInviteCode(
      userId: 'new-user',
      displayName: 'NewUser',
      inviteCode: 'FOGBLT',
    );
    final cluster = result.getRight().toNullable()!;
    expect(cluster.isMember, isTrue);
    expect(cluster.members.any((m) => m.userId == 'new-user'), isTrue);
  });

  test('joinByInviteCode is case-insensitive', () async {
    final result = await svc.joinByInviteCode(
      userId: 'u2',
      displayName: 'U2',
      inviteCode: 'fogblt',
    );
    expect(result.isRight(), isTrue);
  });

  test('joinByInviteCode rejects empty code', () async {
    final result = await svc.joinByInviteCode(
      userId: 'u2',
      displayName: 'U2',
      inviteCode: '   ',
    );
    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('joinByInviteCode rejects unknown invite code', () async {
    final result = await svc.joinByInviteCode(
      userId: 'u2',
      displayName: 'U2',
      inviteCode: 'NOPE99',
    );
    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('joinByInviteCode rejects duplicate join', () async {
    await svc.joinByInviteCode(
      userId: 'u3',
      displayName: 'U3',
      inviteCode: 'FOGBLT',
    );
    final result = await svc.joinByInviteCode(
      userId: 'u3',
      displayName: 'U3',
      inviteCode: 'FOGBLT',
    );
    expect(result.isLeft(), isTrue);
  });

  test('leaveCluster removes user from member list', () async {
    await svc.joinByInviteCode(
      userId: 'u4',
      displayName: 'U4',
      inviteCode: 'FOGBLT',
    );

    final clusters =
        (await svc.getNearbyClusters(userId: 'u4')).getRight().toNullable()!;
    final fog = clusters.firstWhere((c) => c.inviteCode == 'FOGBLT');

    final leaveResult = await svc.leaveCluster(
      userId: 'u4',
      clusterId: fog.id,
    );
    expect(leaveResult.isRight(), isTrue);

    final after =
        (await svc.getNearbyClusters(userId: 'u4')).getRight().toNullable()!;
    final fogAfter = after.firstWhere((c) => c.id == fog.id);
    expect(fogAfter.members.any((m) => m.userId == 'u4'), isFalse);
  });

  // ── Messaging ─────────────────────────────────────────────────────────────

  test('postMessage appends a new message', () async {
    final clusters =
        (await svc.getNearbyClusters(userId: 'u1')).getRight().toNullable()!;
    final fog = clusters.firstWhere((c) => c.inviteCode == 'FOGBLT');

    final before = (await svc.getMessages(clusterId: fog.id)).getRight().toNullable()!;

    await svc.postMessage(
      clusterId: fog.id,
      authorId: 'u1',
      authorName: 'TestUser',
      content: 'Hello cluster!',
    );

    final after = (await svc.getMessages(clusterId: fog.id)).getRight().toNullable()!;
    expect(after.length, before.length + 1);
    expect(after.first.content, 'Hello cluster!');
  });

  test('postMessage rejects empty content', () async {
    final clusters =
        (await svc.getNearbyClusters(userId: 'u1')).getRight().toNullable()!;
    final fog = clusters.first;

    final result = await svc.postMessage(
      clusterId: fog.id,
      authorId: 'u1',
      authorName: 'U1',
      content: '   ',
    );
    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('postMessage rejects content over 500 characters', () async {
    final clusters =
        (await svc.getNearbyClusters(userId: 'u1')).getRight().toNullable()!;
    final fog = clusters.first;

    final result = await svc.postMessage(
      clusterId: fog.id,
      authorId: 'u1',
      authorName: 'U1',
      content: 'x' * 501,
    );
    expect(result.isLeft(), isTrue);
  });

  test('reactToMessage increments emoji count', () async {
    final clusters =
        (await svc.getNearbyClusters(userId: 'u1')).getRight().toNullable()!;
    final fog = clusters.firstWhere((c) => c.inviteCode == 'FOGBLT');
    final msgId = fog.messages.first.id;
    final before = fog.messages.first.reactions['👍'] ?? 0;

    final result = await svc.reactToMessage(
      clusterId: fog.id,
      messageId: msgId,
      emoji: '👍',
    );
    final updated = result.getRight().toNullable()!;
    expect(updated.reactions['👍'], before + 1);
  });

  // ── Challenges ────────────────────────────────────────────────────────────

  test('getChallenges returns active challenges for a cluster', () async {
    final clusters =
        (await svc.getNearbyClusters(userId: 'u1')).getRight().toNullable()!;
    final fog = clusters.firstWhere((c) => c.inviteCode == 'FOGBLT');

    final result = await svc.getChallenges(clusterId: fog.id);
    final challenges = result.getRight().toNullable()!;
    expect(challenges.isNotEmpty, isTrue);
    expect(challenges.every((c) => c.status == ClusterChallengeStatus.active), isTrue);
  });
}
