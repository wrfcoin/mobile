import 'dart:convert';
import 'dart:io';

Map<String, dynamic> roleFixture() => jsonDecode(
  File('contract-fixtures/role-earnings-b2.json').readAsStringSync(),
) as Map<String, dynamic>;
Map<String, dynamic> roleBoard(String role) =>
    Map<String, dynamic>.from(roleFixture()['boards'][role] as Map);
