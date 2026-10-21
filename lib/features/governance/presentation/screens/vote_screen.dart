import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../services/observability/app_logger.dart';
import '../../data/models/proposal_model.dart';
import '../providers/proposals_provider.dart';

class VoteScreen extends ConsumerStatefulWidget {
  final ProposalModel proposal;

  const VoteScreen({super.key, required this.proposal});

  @override
  ConsumerState<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends ConsumerState<VoteScreen> {
  String? _selectedVote;
  final _reasonController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitVote() async {
    if (_selectedVote == null || _submitting) return;
    final vote = _selectedVote!;
    final reason = _reasonController.text.trim();
    setState(() => _submitting = true);
    final logger = ref.read(appLoggerProvider);
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Confirm Vote',
        message: 'Cast "$vote" vote on "${widget.proposal.title}"?',
        confirmLabel: 'Cast Vote',
      );
      if (!confirmed || !mounted) return;
      // The repository opens the wallet key once, with biometrics, after this
      // explicit confirmation. No separate authentication-only prompt here.
      logger.info(
        'governance_vote_attempt',
        fields: <String, dynamic>{
          'proposalId': widget.proposal.id,
          'voteType': vote,
        },
      );
      await ref
          .read(proposalsProvider.notifier)
          .vote(
            proposalId: widget.proposal.id,
            voteType: vote,
            reason: reason.isEmpty ? null : reason,
          );
      if (mounted) {
        logger.info(
          'governance_vote_success',
          fields: <String, dynamic>{
            'proposalId': widget.proposal.id,
            'voteType': vote,
          },
        );
        AppSnackbars.success(
          context,
          'Vote cast successfully',
          detail: '${widget.proposal.title}: $vote',
        );
        context.pop();
      }
    } catch (e) {
      logger.error(
        'governance_vote_failed',
        fields: <String, dynamic>{
          'proposalId': widget.proposal.id,
          'voteType': vote,
          'error': e.toString(),
        },
      );
      if (mounted) {
        AppSnackbars.error(
          context,
          e is Failure ? e : ServerFailure(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cast Vote')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              widget.proposal.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your Vote',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _selectedVote,
              onChanged: (value) {
                if (!_submitting) setState(() => _selectedVote = value);
              },
              child: Column(
                children: [
                  ...[
                    ('FOR', 'Vote For', AppColors.success, Icons.thumb_up),
                    (
                      'AGAINST',
                      'Vote Against',
                      AppColors.error,
                      Icons.thumb_down,
                    ),
                  ].map(
                    (option) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RadioListTile<String>(
                        value: option.$1,
                        selected: _selectedVote == option.$1,
                        title: Row(
                          children: [
                            Icon(option.$4, color: option.$3, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(option.$2)),
                            if (_selectedVote == option.$1)
                              Icon(
                                Icons.check_circle,
                                color: option.$3,
                                size: 18,
                              ),
                          ],
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: _selectedVote == option.$1
                                ? option.$3
                                : AppColors.border,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Explain your vote...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _selectedVote == null || _submitting
                  ? null
                  : _submitVote,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Vote'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Biometric authentication required before voting',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
