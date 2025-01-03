using System;
using System.Diagnostics;
namespace BeefGen;

class PreprocessorEvaluator
{
	public enum ETokenKind
	{
		LParent,
		RParent,
		Not,
		Plus,
		Minus,
		Mult,
		Div,
		Mod,
		CmpEQ,
		CmpNotEQ,
		CmpLess,
		CmpLessEQ,
		CmpGreater,
		CmpGreaterEQ,
		And,
		Or,
		BitShiftLeft,
		BitShiftRight,
		BitXor,
		BitAnd,
		BitOr,
		BitNot,
		Literal,
		Identifier,
	}

	public enum ELiteralKind
	{
		Unknown,
		Bool,
		Int64,
		Float,
		Double,
		String
	}

	public struct LiteralInfo
	{
		public enum EFlags
		{
			None = 0x00,
			Hex = 0x01,
			Unsigned = 0x02,
			LongLong = 0x04
		}

		[Union]
		public struct Data
		{
			public bool boolValue;
			public int64 i64Value;
			public uint64 u64Value;
			public double doubleValue;
			public StringView stringValue;

		}
		public ELiteralKind kind;
		public using Data _data;
		public EFlags flags = default;

		public this(bool value)
		{
			kind = .Bool;
			boolValue = value;
		}

		public this(int64 value)
		{
			kind = .Int64;
			i64Value = value;
		}

		public this(uint64 value)
		{
			kind = .Int64;
			u64Value = value;
			flags = .Unsigned;
		}

		public this(float value)
		{
			kind = .Float;
			doubleValue = value;
		}

		public this(double value)
		{
			kind = .Double;
			doubleValue = value;
		}

		public this(StringView value)
		{
			kind = .String;
			stringValue = value;
		}
	}

	public struct TokenData
	{
		public ETokenKind kind;
		[Union]
		struct Data
		{
			public StringView identifier;
			public LiteralInfo literal;
		}

		public using Data _data;

		public this(ETokenKind k)
		{
			Debug.Assert(k != .Literal && k != .Identifier);
			kind = k;
			_data = default;
		}

		public this(ETokenKind k, StringView identifier)
		{
			Debug.Assert(k == .Identifier);
			kind = k;
			_data.identifier = identifier;
		}

		public this(ETokenKind k, LiteralInfo literal)
		{
			Debug.Assert(k == .Literal);
			kind = k;
			_data.literal = literal;
		}
	}

	public class SourceData
	{
		public StringView input;
		public int position;

		public char8 prevChar;
		public char8 currentChar;

		public this(StringView input)
		{
			this.input = input;
			position = 0;
			prevChar = 0;
			currentChar = input.Length > 0 ? input[0] : 0;
		}

		[Inline]
		public bool HasData => position < input.Length;

		public void NextChar()
		{
			if (position < input.Length)
			{
				++position;
				if (position < input.Length)
				{
					prevChar = currentChar;
					currentChar = input[position];
				}
			}
		}
	}

	void SkipWhitespace(SourceData source)
	{
		while (source.HasData)
		{
			if (!source.currentChar.IsWhiteSpace)
				break;

			source.NextChar();
		}
	}

	Result<TokenData> ParseNumber(SourceData source)
	{
		ELiteralKind kind = .Unknown;
		LiteralInfo.EFlags flags = .None;

		let start = source.position;

		if (source.currentChar == '0')
		{
			source.NextChar();

			if (source.currentChar == 'x' || source.currentChar == 'X')
			{
				flags = .Hex;
				source.NextChar();
			}
		}

		static bool IsHexChar (char8 c) => (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');

		while (source.HasData && (source.currentChar.IsDigit || (flags.HasFlag(.Hex) && IsHexChar(source.currentChar))))
		{
			source.NextChar();
		}

		bool explicitFloat = false;
		bool fp = false;
		bool exponent = false;
		bool unsigned = false;
		int32 long = 0;

		while (source.HasData)
		{
			switch (source.currentChar)
			{
			case 'u', 'U' when (!unsigned && long == 0 && !fp):
				{
					unsigned = true;
					source.NextChar();
					continue;
				}
			case 'l', 'L' when (long < 2 && !fp):
				{
					long++;
					source.NextChar();
					continue;
				}
			case '.' when (!fp && !unsigned && long == 0):
				{
					fp = true;
					source.NextChar();
					while (source.HasData && source.currentChar.IsDigit)
					{
						source.NextChar();
					}

					continue;
				}

			case 'e', 'E' when (!exponent && !unsigned && long == 0):
				{
					exponent = true;
					source.NextChar();
					if (source.currentChar == '-' || source.currentChar == '+')
					{
						source.NextChar();
					}

					while (source.HasData && source.currentChar.IsDigit)
					{
						source.NextChar();
					}

					continue;
				}

			case 'f', 'F' when (!explicitFloat && (fp || exponent) && !unsigned && long == 0):
				{
					explicitFloat = true;
					source.NextChar();
					continue;
				}
			}
			break;
		}

		StringView value = source.input.Substring(start, source.position - start);

		if (fp || exponent)
		{
			if (value.Length == 1)
				return .Err;

			if (explicitFloat)
				value.RemoveFromEnd(1);

			switch(double.Parse(value))
			{
			case .Ok(let val):
				{
					LiteralInfo info = .(val);
					if (explicitFloat)
						info.kind = .Float;

					return TokenData(.Literal, info);
				}
			case .Err:
				{
					Log.Error(scope $"Failed to parse float literal '{value}'");
					return .Err;
				}
			}
		}

		System.Globalization.NumberStyles style = .Number;
		if (flags & .Hex == .Hex)
			style = .HexNumber;

		if (long == 2)
			flags |= .LongLong;
		if (unsigned)
		{
			value.RemoveFromEnd(1);
			flags |= .Unsigned;
		}
		value.RemoveFromEnd(long);

		switch(uint64.Parse(value, style))
		{
		case .Ok(let val):
			{
				LiteralInfo info = .(val);
				info.flags = flags;

				return TokenData(.Literal, info);
			}
		case .Err:
			{
				Log.Error(scope $"Failed to parse integer literal '{value}'");
				return .Err;
			}
		}
	}

	public Result<TokenData> GetToken(SourceData source)
	{
		TokenData Advance(ETokenKind kind)
		{
			source.NextChar();
			return .(kind);
		}

		SkipWhitespace(source);

		switch (source.currentChar)
		{
		case '(': return Advance(.LParent);
		case ')': return Advance(.RParent);

		case '+': return Advance(.Plus);
		case '-': return Advance(.Minus);
		case '*': return Advance(.Mult);
		case '/': return Advance(.Div);
		case '%': return Advance(.Mod);

		case '<':
			{
				source.NextChar();
				if (source.currentChar == '<')
					return Advance(.BitShiftLeft);
				if (source.currentChar == '=')
					return Advance(.CmpLessEQ);

				return TokenData(.CmpLess);
			}
		case '>':
			{
				source.NextChar();
				if (source.currentChar == '>')
					return Advance(.BitShiftRight);
				if (source.currentChar == '=')
					return Advance(.CmpGreaterEQ);

				return TokenData(.CmpGreater);
			}
		case '=':
			{
				source.NextChar();

				if (source.currentChar == '=')
					return Advance(.CmpEQ);

				return .Err;
			}
		case '!':
			{
				source.NextChar();

				if (source.currentChar == '=')
					return Advance(.CmpNotEQ);

				return TokenData(.Not);
			}

		case '~': return Advance(.BitNot);
		case '&':
			{
				source.NextChar();
				if (source.currentChar == '|')
					return Advance(.And);

				return TokenData(.BitAnd);
			}
		case '|':
			{
				source.NextChar();
				if (source.currentChar == '|')
					return Advance(.Or);

				return TokenData(.BitOr);
			}
		case '^': return Advance(.BitXor);
		}

		if (source.currentChar == '"')
		{
			source.NextChar();
			let start = source.position;
			char8 prevC = 0;
			while (source.HasData)
			{
				if (source.currentChar == '"' && source.prevChar != '\\')
				{
					source.NextChar();
					break;
				}

				prevC = source.currentChar;
				source.NextChar();
			}
			StringView literal = source.input.Substring(start, source.position - start - 1);
			return TokenData(.Literal, LiteralInfo(literal));
		}

		if (source.currentChar.IsDigit || source.currentChar == '.')
		{
			return ParseNumber(source);
		}

		if (source.currentChar.IsLetter || source.currentChar == '_')
		{
			bool ValidIdentifierChar(char8 c) =>  (source.currentChar.IsLetterOrDigit || source.currentChar == '_');

			let start = source.position;
			while (source.HasData && ValidIdentifierChar(source.currentChar))
			{
				source.NextChar();
			}

			StringView identifier = source.input.Substring(start, source.position - start);

			if (identifier == "true")
				return TokenData(.Literal, .(true));
			if (identifier == "false")
				return TokenData(.Literal, .(false));

			return TokenData(.Identifier, identifier);
		}

		return .Err;
	}
}