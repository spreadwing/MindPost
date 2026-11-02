import 'api_request.dart';
import 'api_folder.dart';
import 'environment.dart';

/// 统一 API 容器接口（用于 ApiCollection 与 ApiFolder）
abstract class ApiContainer {
  String get id;
  String get name;
  set name(String value);
  String get description;
  set description(String value);
  List<KeyValueItem> get headers;
  set headers(List<KeyValueItem> value);
  List<VariableItem> get variables;
  set variables(List<VariableItem> value);
  String get preRequestScript;
  set preRequestScript(String value);
  String get postRequestScript;
  set postRequestScript(String value);
  List<ApiFolder> get folders;
  set folders(List<ApiFolder> value);
  List<ApiRequest> get requests;
  set requests(List<ApiRequest> value);
}
