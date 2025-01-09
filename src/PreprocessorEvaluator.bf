using System;
using System.Collections;

namespace BeefGen;

class PreprocessorEvaluator
{
	append PreprocessorTokenizer _tokenizer;
	Parser _parser;
	PreprocessorEvaluator _macroExpandEvaluator;

	append List<PreprocessorTokenizer.TokenData> _tokens;

	append String _evalType;
	append String _expandBuffer;

	protected bool _singlePass;

	public Span<PreprocessorTokenizer.TokenData> Tokens => _tokens;
	public StringView EvaluatedType => _evalType;
	public StringView ExpandedBuffer => _expandBuffer;

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

	public Result<void> TokenToString(PreprocessorTokenizer.TokenData t, String buffer, Parser.MacroDef macro, Span<StringView> args)
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
					Try!(TokenToString(macro.tokens[i], buffer, macro, args));
					buffer.Append('"');
				}

			case .Concat:
				{
					i++;
					if (i == macro.tokens.Count)
						return .Err;

					buffer.TrimEnd();
					String tmp = scope .();
					Try!(TokenToString(macro.tokens[i], tmp, macro, args));
					tmp.TrimStart();
					buffer.Append(tmp);
				}

			default:
				Try!(TokenToString(t, buffer, macro, args));
				
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

	Result<void> ExpandMacros()
	{
		for (int32 i = 0; i < _tokens.Count; ++i)
		{
			let t = _tokens[i];
			switch (t.kind)
			{
			case .Identifier:
				{
					let macro = GetMacroByName(t.identifier);
					if (macro == null)
						return .Err;

					if (macro.invalid)
						return .Err;

					if (macro.tokens.IsEmpty)
						return .Err;

					_tokens.RemoveAt(i);


					if (macro.args != null && macro.args.Count > 0)
					{
						Try!(ExpandMacroInline(ref i, macro));
					}
					else
					{
						_tokens.Insert(i, macro.tokens);
						i--;
					}

				}
			default:
			}
		}

		return .Ok;
	}

	public Result<void> Evaluate(Span<PreprocessorTokenizer.TokenData> tokens)
	{
		_tokens.Clear();
		_evalType.Clear();
		_expandBuffer.Clear();

		_tokens.AddRange(tokens);
		Try!(ExpandMacros());
		
		return .Ok;
	}
}