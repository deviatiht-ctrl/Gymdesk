import 'strings_access_v4.dart';
import 'strings_core_v3.dart';
import 'strings_insights.dart';
import 'strings_receipts.dart';

/// Chèn tradiksyon V3 pa zòn, pou evite konfli nan app_strings.dart.
const extraStrings = <String, List<String>>{
  ...stringsCoreV3,
  ...stringsInsights,
  ...stringsAccessV4,
  ...stringsReceipts,
};
