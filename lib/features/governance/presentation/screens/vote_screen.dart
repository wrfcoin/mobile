import 'package:flutter/material.dart';

import '../../data/models/proposal_model.dart';
import '../widgets/voting_closed_notice.dart';

/// The vote route stays so an old deep link lands on a plain explanation.
/// There is no way to submit a vote from here.
class VoteScreen extends StatelessWidget {
  final ProposalModel proposal;

  const VoteScreen({super.key, required this.proposal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vote')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            proposal.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const VotingClosedNotice(),
        ],
      ),
    );
  }
}
