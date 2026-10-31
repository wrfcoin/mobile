import 'package:flutter/material.dart';

class TestnetNotice extends StatelessWidget {
  const TestnetNotice({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            'This is a test network. It may be reset without notice. Balances and tokens have no monetary value. No migration to mainnet is promised or implied. Please attach no production bridges, exchange listings or irreplaceable assets.',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'https://wrfcoin.com/testnet-disclaimer.html',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
