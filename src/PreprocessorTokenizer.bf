using System;
using System.Diagnostics;
using System.Collections;
namespace BeefGen;

class PreprocessorTokenizer
{
	public enum ETokenKind
	{
		LParent,
		RParent,
		Questionmark,
		Stringify,
		Concat,
		Colon,
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
		Arg
	}

	public enum ELiteralKind
	{
		Unknown,
		Bool,
		Char,
		Int64,
		Float,
		Double,
		String
	}

	public enum ELiteralType
	{
		case Undefined,
		Char8,
		Char16,
		Char32,
		CharWide,
		Int32,
		Int64,
		String8,
		String16,
		String32,
		StringWide;

		public bool IsChar
		{
			get
			{
				switch (this)
				{
				case .Char8, .Char16, .Char32, .CharWide: return true;
				default: return false;
				}
			}
		}

		public bool IsString
		{
			get
			{
				switch (this)
				{
				case .String8, .String16, .String32, .StringWide: return true;
				default: return false;
				}
			}
		}
	}

	public struct LiteralInfo
	{
		public enum EFlags
		{
			None = 0x00,
			Unsigned = 0x01,
			LongLong = 0x02,


			Hex = 0x10,
			Octal = 0x20,
			Bin = 0x40
		}

		[Union]
		public struct Data
		{
			public bool boolValue;
			public char32 charValue;
			public int64 i64Value;
			public uint64 u64Value;
			public double doubleValue;
			public StringView stringValue;

		}
		public ELiteralKind kind;
		public using Data _data;
		public EFlags flags = default;
		public ELiteralType type = default;
		public StringView valueView = default;

		public this(bool value)
		{
			kind = .Bool;
			boolValue = value;
		}

		public this(char32 value)
		{
			kind = .Char;
			charValue = value;
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
		public using struct 
		{
			public StringView identifier;
			public StringView arg;
			public LiteralInfo literal;
		} _data;

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

		public enum {
			None = 0,
			Indentifier,
			Start
		} asArgs = .None;

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

	Result<TokenData> ParseNumberLiteral(SourceData source)
	{
		Runtime.Assert(source.currentChar.IsDigit || source.currentChar == '.');

		LiteralInfo.EFlags flags = .None;

		let start = source.position;
		uint64 value = 0;

		if (source.currentChar == '0')
		{
			source.NextChar();

			BASE_SELECT:
			switch (source.currentChar)
			{
			case 'x', 'X':
				{
					flags = .Hex;
					source.NextChar();

					while (source.HasData)
					{
						let c = source.currentChar;
						if (c >= '0' && c <= '9')
						{
							value *= 16;
							value += (.)(c - '0');
						}
						else if (c >= 'a' && c <= 'f')
						{
							value *= 16;
							value += 10 + (.)(c - 'a');
						}
						else if (c >= 'A' && c <= 'F')
						{
							value *= 16;
							value += 10 + (.)(c - 'A');
						}
						else
							break BASE_SELECT;

						source.NextChar();
					}
				}
			case 'b':
				{
					flags = .Bin;
					source.NextChar();

					while (source.HasData)
					{
						let c = source.currentChar;
						if (c >= '0' && c <= '1')
						{
							value *= 2;
							value += (.)(c - '0');
						}
						else
							break BASE_SELECT;

						source.NextChar();
					}
				}

			when (_ >= '0' && _ <= '8'):
				{
					
					while (source.HasData)
					{
						let c = source.currentChar;
						if (c >= '0' && c <= '7')
						{
							value *= 8;
							value += (.)(c - '0');
						}
						else
						{
							flags = .Octal;
							break BASE_SELECT;
						}

						source.NextChar();
					}
				}
			}
		}

		if (flags == .None)
		{
			while (source.HasData && source.currentChar.IsDigit)
			{
				value *= 10;
				value += (.)(source.currentChar - '0');
				source.NextChar();
			}
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
			case 'u', 'U' when (!unsigned && !fp):
				{
					unsigned = true;
					source.NextChar();
					continue;
				}
			case 'l', 'L' when (long == 0 && !fp):
				{
					long++;
					source.NextChar();
					if (source.currentChar == 'l' || source.currentChar == 'L')
					{
						long++;
						source.NextChar();
					}	
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

		StringView valueView = source.input.Substring(start, source.position - start);

		if (fp || exponent)
		{
			if (explicitFloat)
				valueView.RemoveFromEnd(1);
			
			if (valueView.Length == 1)
				return .Err;

			switch(double.Parse(valueView))
			{
			case .Ok(let val):
				{
					LiteralInfo info = .(val);
					if (explicitFloat)
						info.kind = .Float;

					info.valueView = valueView;
					return TokenData(.Literal, info);
				}
			case .Err:
				{
					Log.Error(scope $"Failed to parse float literal '{valueView}'");
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
			flags |= .Unsigned;
		}

		return TokenData(.Literal, LiteralInfo(value) { flags = flags, valueView = valueView });
	}

	Result<TokenData> ParseStringLiteral(SourceData source, char8 literalPrefix, int32 prefixLength)
	{
		Runtime.Assert(source.currentChar == '"');
		source.NextChar();
		let start = source.position;
		while (source.HasData)
		{
			if (source.currentChar == '"' && source.prevChar != '\\')
			{
				source.NextChar();
				break;

			}

			source.NextChar();
		}
		if (start == source.position)
			return .Err;

		StringView literal = source.input.Substring(start, source.position - start - 1);
		ELiteralType type;
		switch (literalPrefix)
		{
		case 'u':
			{
				if (prefixLength == 2)
					type = .String8;
				else
					type = .String16;
			}
		case 'U': type = .String32;
		case 'L': type = .StringWide;
		default: type = .String8;
		}
		return TokenData(.Literal, LiteralInfo(literal) { type = type, valueView = literal });
	}

	Result<char32> ParseHexChar(SourceData source, out int32 length)
	{
		uint32 tmp = 0;
		length = 0;
		while (source.HasData)
		{
			let c = source.currentChar;
			if (c >= '0' && c <= '9')
			{
				tmp *= 16;
				tmp += (.)(c - '0');
			}
			else if (c >= 'a' && c <= 'f')
			{
				tmp *= 16;
				tmp += 10 + (.)(c - 'a');
			}
			else if (c >= 'A' && c <= 'F')
			{
				tmp *= 16;
				tmp += 10 + (.)(c - 'A');
			}
			else
			{
				break;
			}

			length++;
			source.NextChar();
		}
		if (length == 0)
			return .Err;

		return .Ok((char32)tmp);
	}

	Result<TokenData> ParseCharLiteral(SourceData source, char8 literalPrefix, int32 prefixLength)
	{
		Runtime.Assert(source.currentChar == '\'');

		LiteralInfo.EFlags flags = .None;

		source.NextChar();
		char32 value = 0;
		let start = source.position;

		if (source.currentChar == '\\')
		{
			source.NextChar();
			BASE_SELECT:
			switch (source.currentChar)
			{
			case '\'':
				{
					value = '\'';
				}
			case '\"':
				{
					value = '"';
				}
			case '\\':
				{
					value = '\\';
				}
			case 'a':
				{
					value = '\a';
				}
			case 'b':
				{
					value = '\b';
				}
			case 'f':
				{
					value = '\f';
				}
			case 'n':
				{
					value = '\n';
				}
			case 'r':
				{
					value = '\r';
				}
			case 't':
				{
					value = '\t';
				}
			case 'v':
				{
					value = '\v';
				}

			case 'U', 'x':
				{
					source.NextChar();
					flags |= .Hex;
					value = Try!(ParseHexChar(source, let length));
					if (_ == 'x' && value > (.)0xFF)
						return .Err;
					if (_ == 'U' && length != 8)
					{
						return .Err;
					}
				}
			case '0':
				{
					source.NextChar();
					if (source.currentChar == '\'')
					{
						value = '\0';
						break BASE_SELECT;
					}

					if (source.currentChar >= '0' && source.currentChar <= '7')
					{
						flags |= .Octal;

						uint32 tmp = 0;
						while (source.HasData)
						{
							let c = source.currentChar;
							if (c >= '0' && c <= '7')
							{
								tmp *= 8;
								tmp += (.)(c - '0');
							}
						}
						value = (.)tmp;
						break BASE_SELECT;
					}

					return .Err;
				}
			}
		}
		else
		{
			(value, let len) = source.input.GetChar32(source.position);
			for (let i < len)
				source.NextChar();
		}

		if (start == source.position)
			return .Err;

		if (source.currentChar != '\'')
			return .Err;

		source.NextChar();

		ELiteralType type;
		switch (literalPrefix)
		{
		case 'u':
			{
				if (prefixLength == 2)
					type = .Char8;
				else
					type = .Char16;
			}
		case 'U': type = .Char32;
		case 'L': type = .CharWide;
		default: type = .Char8;
		}
		let valueView = source.input.Substring(start, source.position - start - 1);
		return TokenData(.Literal, LiteralInfo(value) {
			type = type,
			valueView = valueView,
			flags = flags
		});
	}

	Result<TokenData> ParseArg(SourceData source)
	{
		let start = source.position;

		int32 nestDepth = 0;
		while (source.HasData)
		{
			let c = source.currentChar;
			if (c.IsWhiteSpace)
			{
				
			}
			else if (c == '(')
			{
				nestDepth++;
			}
			else if (c == ')')
			{
				if (nestDepth == 0)
				{
					source.asArgs = .None;
					break;
				}	

				
				nestDepth--;
			}
			else if (c == ',' && nestDepth == 0)
			{
				break;
			}
			source.NextChar();
		}

		if (start == source.position)
		{
			if (source.currentChar == ')')
			{
				source.NextChar();
				return TokenData(.RParent);
			}
			else if (source.currentChar == ',')
			{
				source.NextChar();
				return TokenData(.Arg) {  };
			}

			return .Err;
		}

		let length = source.position - start;
		if (source.asArgs != .None)
			source.NextChar();

		return TokenData(.Arg) { arg = source.input.Substring(start, length)..Trim() };
	}

	public Result<TokenData> GetToken<FN>(SourceData source, FN isFNMacro) where FN : delegate bool(StringView name) 
	{
		let token = Try!(GetToken(source, source.asArgs == .Start));
		if (isFNMacro != null && source.asArgs == .None && token.kind == .Identifier)
		{
			if (isFNMacro(token.identifier))
				source.asArgs = .Indentifier;
		}
		else if (source.asArgs == .Indentifier)
		{
			if (token.kind == .LParent)
			{
				source.asArgs = .Start;
			}
			else
				source.asArgs = .None;
		}
		else if (source.asArgs == .Start && token.kind != .Arg)
		{
			Runtime.FatalError();
		}

		return token;
	}

	Result<TokenData> GetToken(SourceData source, bool isArgs)
	{
		TokenData Advance(ETokenKind kind)
		{
			source.NextChar();
			return .(kind);
		}

		SkipWhitespace(source);

		if (isArgs)
			return ParseArg(source);

		char8 literalPrefix = 0;
		int32 prefixLength = 0;

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
				if (source.currentChar == '&')
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

		case '#':
			{
				source.NextChar();
				if (source.currentChar == '#')
					return Advance(.Concat);

				return TokenData(.Stringify);
			}

		case 'u', 'U', 'L':
			{
				prefixLength++;
				literalPrefix = _;
				source.NextChar();
				if (_ == 'u' && source.currentChar == '8')
				{
					prefixLength++;
					source.NextChar();
				}
			}
		}

		if (source.currentChar == '"')
		{
			return ParseStringLiteral(source, literalPrefix, prefixLength);
		}

		if (source.currentChar == '\'')
		{
			return ParseCharLiteral(source, literalPrefix, prefixLength);
		}

		if (source.currentChar.IsDigit || source.currentChar == '.')
		{
			return ParseNumberLiteral(source);
		}

		IDENTIFIER_OR_BOOL_LITERAL:
		if (source.currentChar.IsLetter || source.currentChar == '_')
		{
			bool ValidIdentifierChar(char8 c) =>  (source.currentChar.IsLetterOrDigit || source.currentChar == '_');

			let start = (source.position - prefixLength);
			while (source.HasData && ValidIdentifierChar(source.currentChar))
			{
				source.NextChar();
			}

			StringView identifier = source.input.Substring(start, source.position - start);

			if (identifier == "true")
				return TokenData(.Literal, LiteralInfo(true));
			if (identifier == "false")
				return TokenData(.Literal, LiteralInfo(false));

			return TokenData(.Identifier, identifier);
		}
		
		return .Err;
	}
}