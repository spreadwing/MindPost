import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/models/api_request.dart';
import 'package:mindpost/ui/widgets/browser_import_dialog.dart';

void main() {
  group('BrowserRequestParser 浏览器请求导入解析测试', () {
    test('Chrome Copy as cURL (cmd) 格式完整解析', () {
      const rawCurl = r'''curl --url ^"http://192.168.110.25:9528/pandroid-api/dms-service/dataManager/tree/node/getTreeNodeList^" ^
  -H ^"Accept: application/json, text/plain, */*^" ^
  -H ^"Accept-Language: zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,sq;q=0.6^" ^
  -H ^"Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1bml0c1N5c3RlbSI6IkdFRUxZX0NPTlNJU1RFTlQiLCJsb2dpblRpbWUiOjE3OTIwNDUxMDI3OTUsInRva2VuSWQiOiIyMTEwNjE2MjUzMjcxMTQ2NDk2IiwiY2xpZW50SVAiOiIxOTIuMTY4LjExMC4xNTUiLCJpc0FjdGl2ZSI6dHJ1ZSwidXNlcklkIjoiMTg5MDAwMjYzMzc5NzI0Njk3NiIsImFjY291bnQiOiJzeXNhZG1pbiIsImxhdCI6MTc5MjA0NTEwMjc5NSwidXNlcm5hbWUiOiLns7vnu5_nrqHnkIblkZgifQ.I_O-48hB0rh3K1XMWbnYflf5qssKIr_7JCWjv0hEW-0^" ^
  -H ^"Connection: keep-alive^" ^
  -H ^"Content-Type: application/json^" ^
  -b ^"sensorsdata2015jssdkcross=^%^7B^%^22distinct_id^%^22^%^3A^%^221a022dc0e6014b7-00ed097b425ed098-26061051-3688960-1a022dc0e614ed^%^22^%^2C^%^22first_id^%^22^%^3A^%^22^%^22^%^2C^%^22props^%^22^%^3A^%^7B^%^22^%^24latest_traffic_source_type^%^22^%^3A^%^22url^%^E7^%^9A^%^84domain^%^E8^%^A7^%^A3^%^E6^%^9E^%^90^%^E5^%^A4^%^B1^%^E8^%^B4^%^A5^%^22^%^2C^%^22^%^24latest_search_keyword^%^22^%^3A^%^22url^%^E7^%^9A^%^84domain^%^E8^%^A7^%^A3^%^E6^%^9E^%^90^%^E5^%^A4^%^B1^%^E8^%^B4^%^A5^%^22^%^2C^%^22^%^24latest_referrer^%^22^%^3A^%^22url^%^E7^%^9A^%^84domain^%^E8^%^A7^%^A3^%^E6^%^9E^%^90^%^E5^%^A4^%^B1^%^E8^%^B4^%^A5^%^22^%^7D^%^2C^%^22identities^%^22^%^3A^%^22eyIkaWRlbnRpdHlfY29va2llX2lkIjoiMWEwMjJkYzBlNjAxNGI3LTAwZWQwOTdiNDI1ZWQwOTgtMjYwNjEwNTEtMzY4ODk2MC0xYTAyMmRjMGU2MTRlZCJ9^%^22^%^2C^%^22history_login_id^%^22^%^3A^%^7B^%^22name^%^22^%^3A^%^22^%^22^%^2C^%^22value^%^22^%^3A^%^22^%^22^%^7D^%^7D^" ^
  -H ^"Origin: http://192.168.110.25:9528^" ^
  -H ^"Referer: http://192.168.110.25:9528/capabilityCenter/bomNavigation?objectId=SDM-2026042922265imIgM^&itemType=versionDef^&name=1_^%^E7^%^BB^%^93^%^E6^%^9E^%^84^%^E5^%^AE^%^89^%^E5^%^85^%^A8^&treeType=bomTree^" ^
  -H ^"User-Agent: Mozilla/5.0 ^(Windows NT 10.0; Win64; x64^) AppleWebKit/537.36 ^(KHTML, like Gecko^) Chrome/155.0.0.0 Safari/537.36^" ^
  -H ^"lang: zh-CN^" ^
  --data-raw ^"^{^\^"treeType^\^":^\^"bomTree^\^",^\^"parentId^\^":^\^"SDM-202511191919A2Jgdf^\^",^\^"current^\^":1,^\^"size^\^":500,^\^"keepNodeIds^\^":^[^]^}^" ^
  --insecure''';

      final result = BrowserRequestParser.parse(rawCurl);

      // 验证 URL 无前后引号
      expect(result.url,
          'http://192.168.110.25:9528/pandroid-api/dms-service/dataManager/tree/node/getTreeNodeList');
      expect(result.suggestedName, 'getTreeNodeList');
      expect(result.method, HttpMethod.post);

      // 验证 Headers 数量与内容
      expect(result.headers.length, 10);
      final headerMap = {for (var h in result.headers) h.key: h.value};

      expect(headerMap['Accept'], 'application/json, text/plain, */*');
      expect(headerMap['Accept-Language'],
          'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,sq;q=0.6');
      expect(headerMap['Authorization']?.startsWith('Bearer eyJ'), isTrue);
      expect(headerMap['Connection'], 'keep-alive');
      expect(headerMap['Content-Type'], 'application/json');
      expect(headerMap['Origin'], 'http://192.168.110.25:9528');
      expect(headerMap['User-Agent'],
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36');
      expect(headerMap['lang'], 'zh-CN');

      // 验证 Cookie 解析且已解码特殊符号
      expect(headerMap['Cookie']?.contains('sensorsdata2015jssdkcross='), isTrue);
      expect(headerMap['Cookie']?.startsWith('"'), isFalse);
      expect(headerMap['Cookie']?.endsWith('"'), isFalse);

      // 验证 Referer 中的 & 字符及百分号转义
      expect(
          headerMap['Referer'],
          'http://192.168.110.25:9528/capabilityCenter/bomNavigation?objectId=SDM-2026042922265imIgM&itemType=versionDef&name=1_%E7%BB%93%E6%9E%84%E5%AE%89%E5%85%A8&treeType=bomTree');

      // 验证 Body 被正确识别为 JSON 格式并美化缩进
      expect(result.bodyType, BodyType.json);
      expect(result.rawFormat, 'json');
      expect(result.bodyContent.contains('"treeType": "bomTree"'), isTrue);
      expect(result.bodyContent.contains('"parentId": "SDM-202511191919A2Jgdf"'),
          isTrue);
      expect(result.bodyContent.contains('"current": 1'), isTrue);
      expect(result.bodyContent.contains('"size": 500'), isTrue);
    });

    test('标准 Linux/macOS cURL bash 格式解析', () {
      const bashCurl = r'''curl 'https://api.example.com/v1/users?page=1&limit=20' \
  -H 'Accept: application/json' \
  -H 'Authorization: Bearer token123' \
  --data-raw '{"name":"Alice","role":"admin"}' \
  --compressed''';

      final result = BrowserRequestParser.parse(bashCurl);
      expect(result.url, 'https://api.example.com/v1/users');
      expect(result.params.length, 2);
      expect(result.params[0].key, 'page');
      expect(result.params[0].value, '1');
      expect(result.params[1].key, 'limit');
      expect(result.params[1].value, '20');
      expect(result.method, HttpMethod.post);
      expect(result.suggestedName, 'users');
      expect(result.headers.length, 2);
      expect(result.bodyType, BodyType.json);
      expect(result.bodyContent.contains('"name": "Alice"'), isTrue);
    });

    test('紧凑参数语法 (-H"..." 与 --url=... 与 -d"...") 支持', () {
      const compactCurl =
          r'''curl --url="http://test.com/api/login" -H"Content-Type: application/json" -d"{\"username\":\"root\"}"''';

      final result = BrowserRequestParser.parse(compactCurl);
      expect(result.url, 'http://test.com/api/login');
      expect(result.suggestedName, 'login');
      expect(result.headers.length, 1);
      expect(result.headers[0].key, 'Content-Type');
      expect(result.headers[0].value, 'application/json');
      expect(result.bodyType, BodyType.json);
      expect(result.bodyContent.contains('"username": "root"'), isTrue);
    });
  });
}
