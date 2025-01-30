using System;
using System.Interop;
using System.Collections;

namespace BeefGen;

enum EMacroConstType
{
	case Unevaluated,
		 Unknown,
		 Bool,
		 Char8,
		 Char16,
		 Char32,
		 CharWide,
		 SizeT,
		 USizeT,
		 Int32,
		 Uint32,
		 Int64,
		 Uint64,
		 Float,
		 Double,
		 String;

	public bool IsInt
	{
		get
		{
			switch (this)
			{
			case .Int32, .Uint32, .Int64, .Uint64, .SizeT, .USizeT: return true;
			default: return false;
			}
		}
	}

	public bool IsNumber
	{
		get
		{
			switch (this)
			{
			case .Int32, .Uint32, .Int64,
				 .Uint64, .SizeT, .USizeT,
				 .Float, .Double: return true;
			default: return false;
			}
		}
	}

	public bool IsChar
	{
		get
		{
			switch (this)
			{
			case .Char8, Char16, .Char32, .CharWide: return true;
			default: return false;
			}
		}
	}

	public String AsString
	{
		get
		{
			switch(this)
			{
			case .Unknown, .Unevaluated: Runtime.FatalError();
			case .Bool: return nameof(bool);
			case .Char8: return nameof(char8);
			case .Char16: return nameof(char16);
			case .Char32: return nameof(char32);
			case .CharWide: return nameof(c_wchar);
			case .Int32: return nameof(int32);
			case .Int64: return nameof(int64);
			case .SizeT: return nameof(int);
			case .Uint32: return nameof(uint32);
			case .Uint64: return nameof(uint64);
			case .USizeT: return nameof(uint);
			case .Float: return nameof(float);
			case .Double: return nameof(double);
			case .String: return nameof(String);
			}
		}
	}

	public static Result<Self> Assign(Self lhs, Self rhs, bool opResult)
	{
		if (lhs == .Unevaluated || rhs == .Unevaluated)
			return .Err;

		if (lhs == .Unknown && rhs == .Unknown)
			return .Err;

		if (lhs == .Unknown)
			return rhs;

		if (rhs == .Unknown)
			return lhs;

		if (lhs.IsNumber && rhs.IsNumber)
		{
			return Math.Max(lhs, rhs);
		}

		if (lhs.IsChar && rhs.IsChar)
		{
			if ((lhs == .CharWide && rhs != .Char32) || (rhs == .CharWide && lhs != .Char32))
			{
				return .CharWide;
			}
			return Math.Max(lhs, rhs);
		}

		if (lhs != rhs && !opResult)
			return .Err;

		return rhs;
	}

	public Result<void> Assign(Self val, bool opResult = false) mut
	{
		switch (Self.Assign(this, val, opResult))
		{
		case .Ok(out this):
			return .Ok;
		case .Err:
			return .Err;
		}
	}
}

class MacroEvalResult
{
	public readonly Parser.MacroDef macro;

	public EMacroConstType type;

	public append String expanded;

	public this(Parser.MacroDef macro, EMacroConstType type, StringView value)
	{
		this.macro = macro;
		this.type = type;
		this.expanded.Set(value);
	}
}

class PreprocessorEvaluator
{
	enum EEvalError
	{
		NotValid,
		Retry
	}

	append PreprocessorTokenizer _tokenizer;
	Parser _parser;
	PreprocessorEvaluator _macroExpandEvaluator;

	append List<PreprocessorTokenizer.TokenData> _tokens;

	append String _expandBuffer;

	public Span<PreprocessorTokenizer.TokenData> Tokens => _tokens;
	public StringView ExpandedBuffer => _expandBuffer;

	append Dictionary<Parser.MacroDef, MacroEvalResult> _evalDict;
	append List<Parser.MacroDef> _evalList;
	append HashSet<Parser.MacroDef> _visitedMacros;

	public this(Parser parser)
	{
		_parser = parser;
	}

	Parser.MacroDef GetMacroByName(StringView name)
	{
		if (_parser.macros.TryGetValueAlt(name, let val))
			return val;

		return null;
	}

	Result<EMacroConstType> GetTypeAndValue(Span<PreprocessorTokenizer.TokenData> tokens, String buffer)
	{
		EMacroConstType type = .Unknown;

		PreprocessorTokenizer.TokenData prev = default;

		for (let t in tokens)
		{
			switch (t.kind)
			{
			case .Questionmark, .Colon, .Stringify, .Concat, .Arg: return .Err;

			case .LParent: buffer.Append('(');
			case .RParent: buffer.Append(')');
			case .Not: buffer.Append('!');
			case .Plus:
				{
					if (prev.kind == .Literal || prev.kind == .LParent)
						buffer.Append(" + ");
					else
						buffer.Append('+');
				}
			case .Minus:
				{
					if (prev.kind == .Literal || prev.kind == .LParent)
						buffer.Append(" - ");
					else
						buffer.Append('-');
				}
			case .Mult: buffer.Append(" * ");
			case .Div: buffer.Append(" / ");
			case .Mod: buffer.Append(" % ");

			case .BitOr: buffer.Append(" | ");
			case .BitAnd: buffer.Append(" & ");
			case .BitXor: buffer.Append(" ^ ");
			case .BitNot: buffer.Append('~');
			case .BitShiftLeft: buffer.Append(" << ");
			case .BitShiftRight: buffer.Append(" >> ");

			case .And:
				{
					buffer.Append(" && ");
					Try!(type.Assign(.Bool, true));
				}
			case .Or:
				{
					buffer.Append(" || ");
					Try!(type.Assign(.Bool, true));
				}
			case .CmpEQ:
				{
					buffer.Append(" == ");
					Try!(type.Assign(.Bool, true));
				}
			case .CmpNotEQ:
				{
					buffer.Append(" != ");
					Try!(type.Assign(.Bool, true));
				}
			case .CmpLess:
				{
					buffer.Append(" < ");
					Try!(type.Assign(.Bool, true));
				}
			case .CmpLessEQ:
				{
					buffer.Append(" <= ");
					Try!(type.Assign(.Bool, true));
				}
			case .CmpGreater:
				{
					buffer.Append("  > ");
					Try!(type.Assign(.Bool, true));
				}
			case .CmpGreaterEQ:
				{
					buffer.Append(" >= ");
					Try!(type.Assign(.Bool, true));
				}

			case .Literal:
				{
					switch (t.literal.kind)
					{
					case .Char:
						{
							bool HasEscapeSequence(char32 c)
							{
								switch(c)
								{
								case '\0','\a','\b','\f','\n','\r','\t','\v','\\','\'','\"':
									return true;
								default:
									return false;
								}
							}	 

							if (t.literal.charValue <= (.)0xFF && ((t.literal.flags & .Hex == .Hex) ||
								(t.literal.charValue.IsControl && !HasEscapeSequence(t.literal.charValue))))
							{
								buffer.AppendF($"'\\x{((uint32)t.literal.charValue):x}'");
							}
							else if (t.literal.charValue < (.)0x80)
							{
								buffer.Append('\'');
								switch (t.literal.charValue)
								{
								case 0: buffer.Append("\\0");
								case '\a': buffer.Append("\\a");
								case '\b': buffer.Append("\\b");
								case '\f': buffer.Append("\\f");
								case '\n': buffer.Append("\\n");
								case '\r': buffer.Append("\\r");
								case '\t': buffer.Append("\\t");
								case '\v': buffer.Append("\\v");
								case '\\': buffer.Append(@"\\");
								case '\'': buffer.Append("\\'");
								case '\"': buffer.Append("\\\"");
								default: buffer.Append(_);
								}
								buffer.Append('\'');
							}
							else
							{
								buffer.AppendF($"'\\u{{{((uint32)t.literal.charValue):x}}}'");
							}

							switch (t.literal.type)
							{
							case .Char8:
								Try!(type.Assign(.Char8));

							case .Char16:
								Try!(type.Assign(.Char16));

							case .Char32:
								Try!(type.Assign(.Char32));

							case .CharWide:
								Try!(type.Assign(.CharWide));

							case .Int32, .Int64, .String8, .String16, .String32, .StringWide, .Undefined:
								Runtime.FatalError();
							}

						}

					case .Bool:
						{
							buffer.Append(t.literal.boolValue ? "true" : "false");
							if (type == .Unknown)
								Try!(type.Assign(.Bool));
						}
					case .Int64:
						{
							if (t.literal.flags & .Hex == .Hex)
							{
								String prefix = "";
								if ((t.literal.u64Value >= 0x01000000 && t.literal.u64Value <= 0x0F000000) ||
									(t.literal.u64Value >= 0x0100000000 && t.literal.u64Value <= 0x0F00000000))
									prefix = "0";

								buffer.AppendF($"0x{prefix}{t.literal.u64Value:x}");
							}
							else if (t.literal.flags & .Octal == .Octal)
							{
								buffer.Append("0o");
								var tmp = t.literal.u64Value;
								let i = buffer.Length;
								while (tmp != 0)
								{
									char8 c;
									switch (tmp % 8)
									{
									case 0: c = '0';
									case 1: c = '1';
									case 2: c = '2';
									case 3: c = '3';
									case 4: c = '4';
									case 5: c = '5';
									case 6: c = '6';
									case 7: c = '7';
									default: Runtime.FatalError();
									}

									buffer.Insert(i, c);
									tmp /= 8;
								}
							}
							else if (t.literal.flags & .Bin == .Bin)
							{
								buffer.Append("0b");
								var tmp = t.literal.u64Value;
								let i = buffer.Length;
								while (tmp != 0)
								{
									char8 c = (tmp & 1 == 1) ? '1' : '0';
									buffer.Insert(i, c);
									tmp >>= 1;
								}
							}
							else
							{
								buffer.Append(t.literal.u64Value);
							}

							if (type == .Unknown || type.IsInt)
							{
								uint32 maxVal = (t.literal.flags & .Unsigned == .Unsigned) ? uint32.MaxValue : int32.MaxValue;

								if ((t.literal.flags & .LongLong == .LongLong) || (t.literal.u64Value > maxVal))
								{
									if (t.literal.flags & .Unsigned == .Unsigned)
										Try!(type.Assign(.Uint64));
									else
										Try!(type.Assign(.Int64));
								}
								else
								{
									if (t.literal.flags & .Unsigned == .Unsigned)
										Try!(type.Assign(.Uint32));
									else
										Try!(type.Assign(.Int32));
								}
							}
						}
					case .Float:
						{
							buffer.Append(t.literal.valueView);
							buffer.Append('f');
							if (type == .Unknown || (type.IsNumber && type != .Double))
								Try!(type.Assign(.Float));
						}
					case .Double:
						{
							buffer.Append(t.literal.valueView);
							Try!(type.Assign(.Double));
						}
					case .String:
						{
							if ((prev.kind == .Literal && prev.literal.type.IsString) || (prev.kind == .Identifier && type == .String))
							{
								buffer.Append(" + ");
							}

							type = .String;
							buffer.AppendF($"\"{t.literal.stringValue}\"");
						}
					case .Unknown:
						Runtime.FatalError();
					}
				}

			case .Identifier:
				{
					if (_parser.macros.TryGetValueAlt(t.identifier, let macro) && _evalDict.TryGetValue(macro, let eval))
					{
						Try!(type.Assign(eval.type));
						buffer.Append(t.identifier);
						
					}
					else
						return .Err;

				}
			}
			prev = t;
		}

		return type;
	}

	public Result<void> TokenToString_C(PreprocessorTokenizer.TokenData t, String buffer, Parser.MacroDef macro, Span<StringView> args)
	{
		switch (t.kind)
		{
		case .Questionmark, .Colon, .Stringify, .Concat:
			return .Err;

		case .LParent: buffer.Append('(');
		case .RParent: buffer.Append(')');
		case .Not: buffer.Append('!');
		case .Plus: buffer.Append('+');
		case .Minus: buffer.Append('-');
		case .Mult: buffer.Append(" * ");
		case .Div: buffer.Append(" / ");
		case .Mod: buffer.Append(" % ");

		case .BitOr: buffer.Append(" | ");
		case .BitAnd: buffer.Append(" & ");
		case .BitXor: buffer.Append(" ^ ");
		case .BitNot: buffer.Append('~');
		case .BitShiftLeft: buffer.Append(" << ");
		case .BitShiftRight: buffer.Append(" >> ");


		case .And: buffer.Append(" && "); 
		case .Or: buffer.Append(" || "); 
		case .CmpEQ: buffer.Append(" == "); 
		case .CmpNotEQ: buffer.Append(" != ");
		case .CmpLess: buffer.Append(" < ");
		case .CmpLessEQ: buffer.Append(" <= ");
		case .CmpGreater: buffer.Append("  > ");
		case .CmpGreaterEQ: buffer.Append(" >= ");

		case .Literal:
			{
				buffer.Append(t.literal.valueView);
			}
		case .Identifier:
			{
				if (macro != null)
				{
					if (t.identifier == "__VA_ARGS__")
					{
						Runtime.NotImplemented();
					}

					for (let a in macro.args)
					{
						if (a == t.identifier)
						{
							let i = @a.Index;
							if (i >= args.Length)
								return .Err;

							buffer.Append(args[i]);
							return .Ok;
						}	
					}
				}

				buffer.Append(t.identifier);
			  
			}
		case .Arg:
			{
				buffer.Append(t.arg);
			}
		}

		return .Ok;
	}

	Result<void> ExpandMacroInline(ref int32 pos, Parser.MacroDef macro)
	{
		_tokens.RemoveAt(pos); // remove (

		List<StringView> args = scope .(macro.args.Count);

		LOOP:
		while (pos < _tokens.Count)
		{
			let t = _tokens[pos];
			switch (t.kind)
			{
			case .Arg:
				{
					_tokens.RemoveAt(pos);
					args.Add(t.arg);
				}
			case .RParent:
				{
					_tokens.RemoveAt(pos);
					break LOOP;
				}

			default:
				return .Err;
			}	
		}

	   if (args.Count < macro.args.Count)
			return .Err;

		String buffer = new:_parser .();

		for (int i = 0; i < macro.tokens.Count; ++i)
		{
			let t = macro.tokens[i];
			switch (t.kind)
			{
			case .Stringify:
				{
					i++;
					if (i == macro.tokens.Count)
						return .Err;

					buffer.Append('"');
					Try!(TokenToString_C(macro.tokens[i], buffer, macro, args));
					buffer.Append('"');
				}

			case .Concat:
				{
					i++;
					if (i == macro.tokens.Count)
						return .Err;

					buffer.TrimEnd();
					String tmp = scope .();
					Try!(TokenToString_C(macro.tokens[i], tmp, macro, args));
					tmp.TrimStart();
					buffer.Append(tmp);
				}

			default:
				Try!(TokenToString_C(t, buffer, macro, args));
				
			}
		}

		PreprocessorTokenizer.SourceData source = scope .(buffer);
		let startPos = pos;
		while (source.HasData)
		{
			let token = Try!(_tokenizer.GetToken(source, (name) => {
				if (_parser.macros.TryGetValueAlt(name, let macro))
					return macro.IsFnLike;

				return false;
			}));
			_tokens.Insert(pos, token);
			pos++;
		}
		pos = startPos;

		return .Ok;
	}

	Result<void, EEvalError> ExpandMacros()
	{
		bool needsRetry = false;
		for (int32 i = 0; i < _tokens.Count; ++i)
		{
			let t = _tokens[i];
			switch (t.kind)
			{
			case .Identifier:
				{
					let macro = GetMacroByName(t.identifier);
					if (macro == null)
						return .Err(.NotValid);

					if (macro.invalid)
						return .Err(.NotValid);

					if (macro.tokens.IsEmpty)
						return .Err(.NotValid);


					if (macro.args != null && macro.args.Count > 0)
					{
						_tokens.RemoveAt(i);

						if ((ExpandMacroInline(ref i, macro)) case .Err)
							return .Err(.NotValid);
					}
					else
					{
						let evaluated = _evalDict.TryGetValue(macro, let eval);

						if (macro.isFiltered || (evaluated && eval.type == .Unknown))
						{
							_tokens.RemoveAt(i);
							_tokens.Insert(i, macro.tokens);
							i--;
						}
						else if (evaluated && eval.type != .Unknown)
						{
							// Dont do anything
						}
						else
						{
							if (_visitedMacros.Add(macro))
							{
								needsRetry = true;
								_evalList.Add(macro);
							}
						}
					}

				}
			default:
			}
		}

		if (needsRetry)
			return .Err(.Retry);

		return .Ok;
	}

	Result<EMacroConstType, EEvalError> Evaluate(Span<PreprocessorTokenizer.TokenData> tokens)
	{
		_tokens..Clear().AddRange(tokens);
		Try!(ExpandMacros());

		switch (GetTypeAndValue(Tokens, _expandBuffer..Clear()))
		{
		case .Ok(let type):
			return type;
		case .Err:
			return .Err(.NotValid);
		}
	}


	public void EvalAll<FilterFN>(FilterFN fn) where FilterFN : delegate bool (Parser.MacroDef macro)
	{
		for (let kv in _parser.macros)
		{
			if (fn(kv.value))
				_evalList.Add(kv.value);
		}

		while (_evalList.Count > 0)
		{
			let macro = _evalList.PopFront();

			if (_evalDict.TryGetValue(macro, let eval))
				continue;

			switch (Evaluate(macro.tokens))
			{
				case .Ok(let evalType):
				{
					Runtime.Assert(evalType != .Unevaluated);
					if (evalType == .Unknown)
						continue;

					let result = new:_parser MacroEvalResult(macro, evalType, _expandBuffer);
					_evalDict.Add(macro, result);
				}
			case .Err(let err):
				{
					if (err == .Retry && _visitedMacros.Add(macro))
						_evalList.Add(macro);
				}
			}
		}
	}

	public void ForEach<FN>(FN fn) where FN : delegate void (MacroEvalResult macroEval)
	{
		for (let kv in _evalDict)
			fn(kv.value);
	}
}