/// Safely parses a JSON value to a double, tolerating num, String, or null.
double parseDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}
