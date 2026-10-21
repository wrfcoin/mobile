enum PwsBrand { ecowitt, davis, unknown }

class PwsStation {
  const PwsStation({
    required this.brand,
    required this.name,
    required this.host,
    required this.port,
  });

  final PwsBrand brand;
  final String name;
  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is PwsStation &&
      other.brand == brand &&
      other.name == name &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(brand, name, host, port);

  @override
  String toString() => 'PwsStation($brand, $name, $host:$port)';
}
