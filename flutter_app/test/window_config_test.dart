import 'package:edithub/window_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop window starts at its minimum supported size', () {
    expect(kEditHubWindowSize, const Size(1152, 760));
    expect(kEditHubMinimumSize, kEditHubWindowSize);
  });
}
