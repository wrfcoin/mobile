import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/advisory_vote.dart';

Map<String, dynamic> _eligibility({
  bool open = true,
  bool eligible = true,
  String? voted,
  String? reason,
}) => <String, dynamic>{
  'votingOpen': open,
  'eligible': eligible,
  'voted': voted,
  'canVote': open && eligible && voted == null && reason == null,
  'reason': reason,
  'nextNonce': 0,
};

void main() {
  const snapshotReason =
      'this wallet held under 1 WRF spendable when the proposal was created';

  test('not eligible names the creation block and what happens next', () {
    final e = AdvisoryEligibility.fromJson(
      _eligibility(eligible: false, reason: snapshotReason),
    );
    final r = e.refusalFor(createdAtBlock: 27028)!;
    expect(r.kind, AdvisoryRefusalKind.notEligible);
    expect(
      r.message,
      "This wallet can't vote on this proposal: it held less than 1 WRF when "
      'the proposal was created (block 27028). It can vote on proposals '
      'created from now on, while it holds 1 WRF or more.',
    );
  });

  test('not eligible without a known block invents none', () {
    final e = AdvisoryEligibility.fromJson(
      _eligibility(eligible: false, reason: snapshotReason),
    );
    expect(e.refusal!.message, isNot(contains('block')));
    expect(e.refusal!.message, contains('held less than 1 WRF'));
    expect(e.refusalFor()!.message, e.refusal!.message);
  });

  test('closed and already voted keep their own words', () {
    expect(
      AdvisoryEligibility.fromJson(
        _eligibility(open: false, reason: 'voting has closed'),
      ).refusalFor(createdAtBlock: 5)!.message,
      'Voting on this proposal has closed.',
    );
    expect(
      AdvisoryEligibility.fromJson(
        _eligibility(voted: 'for', reason: 'this wallet already voted'),
      ).refusalFor(createdAtBlock: 5)!.message,
      'This wallet already voted for.',
    );
  });

  test('an unknown reason is passed on honestly', () {
    final r = AdvisoryEligibility.fromJson(
      _eligibility(reason: 'something new'),
    ).refusalFor(createdAtBlock: 5)!;
    expect(r.kind, AdvisoryRefusalKind.other);
    expect(r.message, "This wallet can't vote: something new.");
  });

  test('eligible wallet: no refusal', () {
    expect(AdvisoryEligibility.fromJson(_eligibility()).refusal, isNull);
  });
}
