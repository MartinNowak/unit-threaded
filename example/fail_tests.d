import ut.testcase;

class WrongTest: TestCase {
    override void test() {
        assertTrue(5 == 3);
        assertFalse(5 == 5);
        assertEqual(5, 5);
        assertNotEqual(5, 3);
        assertEqual(5, 3);
    }
}

class OtherWrongTest: TestCase {
    override void test() {
        assertTrue(false);
    }
}

class RightTest: TestCase {
    override void test() {
        assertTrue(true);
    }
}

private void testFoo() {}
private void someFun() {}

unittest {
    //TODO: reenable
    //assert(false, "unittest block that always fails");
}