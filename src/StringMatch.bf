using System;

namespace System;

extension StringView
{
	public bool Match(StringView pattern, bool ignoreCase = true, bool allowForwardSlash = false)
	{
		// * match zero or more
		// ? match one

		let strLen = this.Length;
		let patternLen = pattern.Length;

		int32 strPos = 0;
		int32 patternPos = 0;

		char8 lastPatternChar = 0;

		while ((strPos < strLen) && (patternPos < patternLen))
		{
			let c = pattern[patternPos];
			patternPos++;

			if (c == '*' && lastPatternChar != '\\')
			{
				// Skip additional *
				while (patternPos < patternLen && pattern[patternPos] == '*')
				{
					patternPos++;
				}

				{
					let subStr = Substring(strPos);
					let subPattern = pattern.Substring(patternPos);
					if (subStr.Match(subPattern, ignoreCase, allowForwardSlash))
					{
						return true;
					}
				}

				let subStr = Substring(strPos + 1);
				let subPattern = pattern.Substring(patternPos - 1);
				return subStr.Match(subPattern, ignoreCase, allowForwardSlash);
			}
			else if (c == '?' && lastPatternChar != '\\')
			{
				strPos++;
			}
			else if (c == '\\' && lastPatternChar != '\\')
			{
			}
			else
			{
				let strC = this[strPos];
				if ((c == strC) || (ignoreCase && (c.ToLower == strC.ToLower)) || (allowForwardSlash && (c == '/') && (strC == '\\')))
				{
				}
				else
				{
					return false;
				}

				strPos++;
			}

			if (lastPatternChar == '\\' && c == '\\')
			{
				lastPatternChar = 0;
			}
			else
			{
				lastPatternChar = c;
			}
		}

		while (patternPos < patternLen)
		{
			let c = pattern[patternPos++];
			if (c != '*')
				return false;
		}

		return (strPos == strLen);
	}
}

extension String
{
	[Inline]
	public bool Match(StringView pattern, bool ignoreCase = true, bool allowForwardSlash = false) => (StringView(this)).Match(pattern, ignoreCase, allowForwardSlash);
}