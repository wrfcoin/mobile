/// Chain identity shared by transfers, station actions and wallet login.
/// Release and profile compilation requires an explicit chain define on every platform.
class TransferSigningDomain {
  const TransferSigningDomain({required this.chainId, required this.networkId});

  const TransferSigningDomain._configured({
    required this.chainId,
    required this.networkId,
  }) : assert(chainId != '', 'WRFCOIN_CHAIN_ID is required for release and profile builds');

  final String chainId;
  final String networkId;

  static const TransferSigningDomain configured = TransferSigningDomain._configured(
    chainId: String.fromEnvironment(
      'WRFCOIN_CHAIN_ID',
      defaultValue: (bool.fromEnvironment('dart.vm.product') ||
              bool.fromEnvironment('dart.vm.profile'))
          ? ''
          : '777',
    ),
    networkId: String.fromEnvironment('WRFCOIN_NETWORK_ID', defaultValue: 'testnet'),
  );
}
