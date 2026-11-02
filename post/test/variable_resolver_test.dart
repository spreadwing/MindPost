import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/engine/variable_resolver.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/models/environment.dart';
import 'package:mindpost/models/api_collection.dart';
import 'package:mindpost/models/api_folder.dart';
import 'package:mindpost/models/api_container.dart';

void main() {
  group('VariableResolver 深度边界与动态函数测试', () {
    test('基础占位符插值替换', () {
      final vars = {'token': 'secret123', 'userId': '9981'};
      final result = VariableResolver.interpolate(
        'https://api.test.com/users/{{userId}}?token={{token}}',
        vars,
      );
      expect(result, 'https://api.test.com/users/9981?token=secret123');
    });

    test('未定义占位符保持原样不崩溃', () {
      final vars = {'token': 'secret123'};
      final result = VariableResolver.interpolate(
        'https://api.test.com/users/{{undefined}}?token={{token}}',
        vars,
      );
      expect(result, 'https://api.test.com/users/{{undefined}}?token=secret123');
    });

    test(r'系统内置动态变量解析 ($timestamp, $guid, $randomInt)', () {
      final tsStr = VariableResolver.interpolate(r'{{$timestamp}}', {});
      expect(int.tryParse(tsStr), isNotNull);

      final guidStr = VariableResolver.interpolate(r'{{$guid}}', {});
      expect(guidStr.length, 36);
      expect(guidStr.contains('-'), isTrue);

      final randStr = VariableResolver.interpolate(r'{{$randomInt}}', {});
      final rand = int.tryParse(randStr);
      expect(rand, isNotNull);
      expect(rand! >= 1000 && rand <= 9999, isTrue);
    });

    test('resolveUrl: 显式绝对 URL 保持完整', () {
      final url = VariableResolver.resolveUrl(
        rawUrl: 'https://gateway.example.com/api/v1',
        variables: {'baseUrl': 'http://ignored.com'},
      );
      expect(url, 'https://gateway.example.com/api/v1');
    });

    test('resolveUrl: 相对路径与 baseUrl 自动拼接', () {
      final url = VariableResolver.resolveUrl(
        rawUrl: 'api/login',
        variables: {'baseUrl': 'https://gateway.example.com'},
      );
      expect(url, 'https://gateway.example.com/api/login');
    });

    test('buildVariableMap: 遵循 环境变量 > 集合公共变量 > 全局变量 级联优先级', () {
      final env = Environment(
        id: 'env-dev-1',
        name: 'Dev',
        baseUrl: 'https://dev.api.com',
        variables: [
          VariableItem(key: 'commonKey', value: 'fromEnv'),
        ],
      );

      final ws = Workspace(
        name: '测试工作区',
        globalVariables: [
          VariableItem(key: 'commonKey', value: 'fromGlobal'),
          VariableItem(key: 'globalOnly', value: 'globalVal'),
        ],
        environments: [env],
        activeEnvironmentId: env.id,
      );

      final col = ApiCollection(
        name: '用户集合',
        variables: [
          VariableItem(key: 'commonKey', value: 'fromCollection'),
          VariableItem(key: 'colOnly', value: 'colVal'),
        ],
      );

      final subFolder = ApiFolder(
        name: '二级子目录',
        variables: [
          VariableItem(key: 'commonKey', value: 'fromSubFolder'),
        ],
      );

      final containers = <ApiContainer>[col, subFolder];

      final resolved = VariableResolver.buildVariableMap(
        workspace: ws,
        parentContainers: containers,
      );

      expect(resolved['globalOnly'], 'globalVal');
      expect(resolved['colOnly'], 'colVal');
      expect(resolved['baseUrl'], 'https://dev.api.com');
      // 子容器覆盖集合与环境变量
      expect(resolved['commonKey'], 'fromSubFolder');
    });
  });
}
