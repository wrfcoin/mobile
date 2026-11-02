import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Says plainly why nobody can vote, in place of a vote action.
///
/// Voting power on the chain is locked stake only, so ordinary wallets have
/// none. The node's vote route also doesn't use the wallet's current nonce, so
/// a vote could be accepted and then dropped. Until both are fixed, the app
/// must not offer a vote or report one as cast.
class VotingClosedNotice extends StatelessWidget {
  const VotingClosedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Voting isn't open on testnet yet",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              "Only locked stake counts as voting power right now, and "
              "ordinary wallets don't have any. Voting will open once a "
              "wallet's vote can really be counted.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
