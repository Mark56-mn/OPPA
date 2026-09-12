import "package:flutter_test/flutter_test.dart";

import "package:oppa_mobile/core/demo_mode.dart";

void main() {
  test("demo mode is a compile-time constant, off by default", () {
    // Tests (and every normal build) run without OPPA_DEMO_MODE, so the
    // default must keep demo mode OFF. A hidden runtime switch would fail
    // this contract; DemoMode is a const-only class.
    expect(DemoMode.enabled, isFalse);
    expect(DemoMode.isProductBuild, isFalse,
        reason: "flutter_test runs on the VM, not an AOT product build");
  });

  test("demo OTP is a development-only 6-digit constant", () {
    expect(DemoMode.demoOtp, hasLength(6));
    expect(int.tryParse(DemoMode.demoOtp), isNotNull);
  });

  test("banner label is defined for the visible demo indicator", () {
    expect(DemoMode.bannerLabel, isNotEmpty);
  });
}
