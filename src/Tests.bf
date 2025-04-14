using System;
namespace BeefGen;

class Tests
{
	static bool StringMatch(StringView str, StringView pattern, bool ignoreCase = true, bool allowForwadSlash = false) => str.Match(pattern, ignoreCase, allowForwadSlash); 

	[Test]
	static void TestStringMatch()
	{
		Test.Assert(StringMatch("foo.bar", "foo.bar"));
		Test.Assert(StringMatch("foo.bar", "*.bar"));
		Test.Assert(StringMatch("foo.bar", "*foo.bar"));
		Test.Assert(StringMatch("foo*.bar", "foo\\*.bar"));
		Test.Assert(StringMatch("foo.bar", "foo?bar"));
		Test.Assert(StringMatch("foo.bar.baz", "foo.*.baz"));


		Test.Assert(StringMatch("C:\\include\\hello.baz", "*include/*.baz", true, true));
		Test.Assert(StringMatch("C:\\include\\hello.baz", "*include/*.baf", true, true) == false);

		Test.Assert(StringMatch("hello", "he*o"));
		Test.Assert(StringMatch("hello", "he?lo"));
		Test.Assert(StringMatch("hello", "h*llo"));
		Test.Assert(StringMatch("hello", "*lo"));
		Test.Assert(StringMatch("hello", "he*"));
		Test.Assert(StringMatch("helloworld", "he*world"));
		Test.Assert(StringMatch("hello", "h?l*o"));
		Test.Assert(StringMatch("anything", "*"));
		Test.Assert(StringMatch("hello", "?????"));
		Test.Assert(StringMatch("heeeeo", "he*?o"));

		Test.Assert(StringMatch("heo", "he*?o") == false);
		Test.Assert(StringMatch("hello", "h*z") == false);
		Test.Assert(StringMatch("hello", "????") == false);

		Test.Assert(StringMatch("", "*"));
		Test.Assert(StringMatch("", ""));
		Test.Assert(StringMatch("a", "") == false);
		Test.Assert(StringMatch("abc", "*"));
		Test.Assert(StringMatch("", "?") == false);
		Test.Assert(StringMatch("a", "?"));
		Test.Assert(StringMatch("a", "??") == false);
		Test.Assert(StringMatch("a", "*?"));
		Test.Assert(StringMatch("a", "?*"));
		Test.Assert(StringMatch("a", "*a"));
		Test.Assert(StringMatch("ba", "*a"));
		Test.Assert(StringMatch("bc", "*a") == false);
		Test.Assert(StringMatch("banana", "*a*"));
		Test.Assert(StringMatch("banana", "b*na"));
		Test.Assert(StringMatch("banana", "b*n*"));
		Test.Assert(StringMatch("banana", "*n*n*"));

		// Repeated stars
		Test.Assert(StringMatch("abc", "**"));
		Test.Assert(StringMatch("abc", "***"));
		Test.Assert(StringMatch("abc", "*?*"));
		Test.Assert(StringMatch("", "*?*") == false);

		// Only wildcards
		Test.Assert(StringMatch("hello", "*****"));
		Test.Assert(StringMatch("", "*****"));

		// Exact length match
		Test.Assert(StringMatch("hello", "?????"));
		Test.Assert(StringMatch("helloo", "?????") == false);

		// Matching nothing
		Test.Assert(StringMatch("", "a*") == false);
		Test.Assert(StringMatch("", "*b") == false);
		Test.Assert(StringMatch("", "*?") == false);

		// Overlapping logic
		Test.Assert(StringMatch("abc", "*a*b*c*"));
		Test.Assert(StringMatch("a1b2c3", "*a*b*c*"));
		Test.Assert(StringMatch("acb", "*a*b*c*") == false);
		Test.Assert(StringMatch("acb", "a**b"));
		Test.Assert(StringMatch("acb", "*a**b*"));
	}
}