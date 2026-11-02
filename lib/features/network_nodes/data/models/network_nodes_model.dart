import '../../../../core/network/public_read.dart';

/// Read model for `GET /api/network/nodes` (backend network-nodes-routes.ts,
/// checked against the live route on 2026-11-02):
///
/// ```json
/// { "chain": { "networkId": "testnet", "chainId": "888", "height": 11601,
///              "status": "ok" },
///   "producers": { "status": "ok", "rosterSource": "…",
///     "window": { "fromHeight": 1, "toHeight": 64, "read": 63, "unreadable": 1,
///                 "unsigned": 0 },
///     "members": [ { "producerId": "…", "publicKey": "<hex>",
///       "payoutAddress": "0x…", "blocksInWindow": 63 | null,
///       "lastBlock": { "height": 64, "time": "<iso>" } | null,
///       "earnedTotal": "<base units>" | null } ],
///     "unrostered": [ { "publicKey": "<hex>", "blocksInWindow": 1,
///                       "lastBlock": { … } } ] },
///   "bonded": { "status": "ok", "epoch": 22,
///     "nodes": [ { "deploymentId": "<hex>", "alias": "…" | null,
///       "principal": "<base units>" | null, "jailed": false | null,
///       "payoutAddress": "0x…" | null, "earnedTotal": "<base units>" | null,
///       "lastPayout": { "epoch": 21, "status": "PROVISIONAL",
///                       "amount": "<base units>" } | null } ] },
///   "attesters": { "status": "ok", "quorum": 2, "ids": [ "…" ] },
///   "checkedAt": "<iso>" }
/// ```
///
/// Each section is `"status": "unavailable"` when the chain node could not
/// answer it, and a value the node did not give stays null, never zero.
class NetworkNodes {
  const NetworkNodes({
    required this.chain,
    required this.producers,
    required this.bonded,
    required this.attesters,
    required this.checkedAt,
  });

  final ChainInfo chain;
  final Producers producers;
  final BondedNodes bonded;
  final Attesters attesters;
  final String? checkedAt;

  factory NetworkNodes.fromJson(Map<String, dynamic> json) => NetworkNodes(
    chain: ChainInfo.fromJson(jsonObject(json['chain']) ?? const {}),
    producers: Producers.fromJson(jsonObject(json['producers']) ?? const {}),
    bonded: BondedNodes.fromJson(jsonObject(json['bonded']) ?? const {}),
    attesters: Attesters.fromJson(jsonObject(json['attesters']) ?? const {}),
    checkedAt: jsonText(json['checkedAt']),
  );
}

class ChainInfo {
  const ChainInfo({
    required this.ok,
    required this.networkId,
    required this.chainId,
    required this.height,
  });

  final bool ok;
  final String? networkId;
  final String? chainId;
  final int? height;

  factory ChainInfo.fromJson(Map<String, dynamic> json) => ChainInfo(
    ok: json['status'] == 'ok',
    networkId: jsonText(json['networkId']),
    chainId: jsonText(json['chainId']),
    height: jsonInt(json['height']),
  );
}

class BlockRef {
  const BlockRef({required this.height, required this.time});

  final int? height;
  final String? time;

  static BlockRef? fromJson(Object? value) {
    final json = jsonObject(value);
    if (json == null) return null;
    return BlockRef(
      height: jsonInt(json['height']),
      time: jsonText(json['time']),
    );
  }
}

class ProducerWindow {
  const ProducerWindow({
    required this.fromHeight,
    required this.toHeight,
    required this.read,
    required this.unreadable,
    required this.unsigned,
  });

  final int? fromHeight;
  final int? toHeight;
  final int? read;
  final int? unreadable;
  final int? unsigned;
}

class Producer {
  const Producer({
    required this.producerId,
    required this.publicKey,
    required this.blocksInWindow,
    required this.lastBlock,
    required this.earnedTotal,
  });

  /// Null for a key that signs blocks but is not in the genesis roster.
  final String? producerId;
  final String publicKey;
  final int? blocksInWindow;
  final BlockRef? lastBlock;
  final String? earnedTotal;

  factory Producer.fromJson(Map<String, dynamic> json) => Producer(
    producerId: jsonText(json['producerId']),
    publicKey: jsonText(json['publicKey']) ?? '',
    blocksInWindow: jsonInt(json['blocksInWindow']),
    lastBlock: BlockRef.fromJson(json['lastBlock']),
    earnedTotal: jsonText(json['earnedTotal']),
  );
}

class Producers {
  const Producers({
    required this.ok,
    required this.window,
    required this.members,
    required this.unrostered,
  });

  final bool ok;
  final ProducerWindow? window;
  final List<Producer> members;
  final List<Producer> unrostered;

  /// Rostered producers that signed at least one block in the window.
  int get producing => members.where((m) => (m.blocksInWindow ?? 0) > 0).length;

  factory Producers.fromJson(Map<String, dynamic> json) {
    final window = jsonObject(json['window']);
    return Producers(
      ok: json['status'] == 'ok',
      window: window == null
          ? null
          : ProducerWindow(
              fromHeight: jsonInt(window['fromHeight']),
              toHeight: jsonInt(window['toHeight']),
              read: jsonInt(window['read']),
              unreadable: jsonInt(window['unreadable']),
              unsigned: jsonInt(window['unsigned']),
            ),
      members: jsonObjects(json['members']).map(Producer.fromJson).toList(),
      unrostered: jsonObjects(json['unrostered'])
          .map(Producer.fromJson)
          .toList(),
    );
  }
}

class BondPayout {
  const BondPayout({
    required this.epoch,
    required this.status,
    required this.amount,
  });

  final int? epoch;
  final String? status;
  final String? amount;

  bool get pending => status == 'PROVISIONAL';
}

class BondedNode {
  const BondedNode({
    required this.deploymentId,
    required this.alias,
    required this.principal,
    required this.jailed,
    required this.payoutAddress,
    required this.earnedTotal,
    required this.lastPayout,
  });

  final String deploymentId;
  final String? alias;
  final String? principal;
  final bool jailed;
  final String? payoutAddress;
  final String? earnedTotal;
  final BondPayout? lastPayout;

  factory BondedNode.fromJson(Map<String, dynamic> json) {
    final payout = jsonObject(json['lastPayout']);
    return BondedNode(
      deploymentId: jsonText(json['deploymentId']) ?? '',
      alias: jsonText(json['alias']),
      principal: jsonText(json['principal']),
      jailed: json['jailed'] == true,
      payoutAddress: jsonText(json['payoutAddress']),
      earnedTotal: jsonText(json['earnedTotal']),
      lastPayout: payout == null
          ? null
          : BondPayout(
              epoch: jsonInt(payout['epoch']),
              status: jsonText(payout['status']),
              amount: jsonText(payout['amount']),
            ),
    );
  }
}

class BondedNodes {
  const BondedNodes({
    required this.ok,
    required this.epoch,
    required this.nodes,
  });

  final bool ok;
  final int? epoch;
  final List<BondedNode> nodes;

  factory BondedNodes.fromJson(Map<String, dynamic> json) => BondedNodes(
    ok: json['status'] == 'ok',
    epoch: jsonInt(json['epoch']),
    nodes: jsonObjects(json['nodes']).map(BondedNode.fromJson).toList(),
  );
}

class Attesters {
  const Attesters({required this.ok, required this.quorum, required this.ids});

  final bool ok;
  final int? quorum;
  final List<String> ids;

  factory Attesters.fromJson(Map<String, dynamic> json) {
    final ids = json['ids'];
    return Attesters(
      ok: json['status'] == 'ok',
      quorum: jsonInt(json['quorum']),
      ids: ids is List ? ids.whereType<String>().toList() : const [],
    );
  }
}
