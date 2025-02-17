using System;
using System.IO;
using System.Collections;
using System.Interop;

namespace BeefGen;

class Generator
{
	enum EProtectionKind
	{
		Unspecified,
		Private,
		Protected,
		Public,
	}

	const String INDENT_STR = "\t";
	append String _indent;

	const String[?] KEYWORDS = .("internal", "function", "delegate", "where",
							"operator", "class", "struct", "extern",
							"for", "while", "do", "repeat", "abstract",
							"base", "virtual", "override", "extension",
							"namespace", "using", "out", "in", "ref",
							"checked");

	Parser _parser;
	Settings _settings;
	StreamWriter _writer;

	append HashSet<String> _handleTypes;

	bool skipNames = false;
	bool skipEndl = false;
	EProtectionKind forceProtection = .Unspecified;
	bool forceUsing;

	//append HashSet<String> _createdTypes;

	void PushIndent()
	{
		_indent.Append(INDENT_STR);
	}

	void PopIndent()
	{
		_indent.RemoveFromEnd(INDENT_STR.Length);
	}

	void WriteIndent()
	{
		_writer.Write(_indent);
	}

	void WriteEnd(StringView value)
	{
		if (skipEndl)
		{
			_writer.Write(value);
			return;
		}

		_writer.WriteLine(value);
	}

	void WriteName(StringView name)
	{
		if (skipNames)
			return;

		_writer.Write(name);
	}

	void WriteProtection(EProtectionKind prot)
	{
		var prot;
		if (this.forceProtection != .Unspecified)
			prot = this.forceProtection;

		String protStr;
		switch (prot)
		{
		case .Public: protStr = "public ";
		case .Protected: protStr = "protected ";
		case .Private: protStr = "private ";
		case .Unspecified: protStr = " ";
		}

		_writer.Write(protStr); 

		if (this.forceUsing)
			_writer.Write("using ");
	}

	void WriteAttrs(Span<String> attrs, bool _inline = false)
	{
		const String ATTR_SUFFIX = nameof(Attribute);

		if (attrs.Length > 0)
		{
			if (!_inline)
				WriteIndent();

			_writer.Write("[");
			for (let a in attrs)
			{
				if (@a.Index != 0)
					_writer.Write(", ");

				StringView attrView = a;

				if (attrView.EndsWith(ATTR_SUFFIX))
					attrView.RemoveFromEnd(ATTR_SUFFIX.Length);

				_writer.Write(attrView);
			}

			_writer.Write("]");
			if (!_inline)
				_writer.WriteLine();
		}
	}

	void WriteIdentifier(StringView name, String buffer)
	{
		StringStream ss = scope .(buffer, .Reference);
		ss.Position = buffer.Length;
		StreamWriter writer = scope .(ss, System.Text.Encoding.UTF8, 64);
		using(SetRestore<StreamWriter>(ref _writer, writer))
		{
			WriteIdentifier(name);
		}
	}

	void WriteIdentifier(StringView name)
	{
		if (name.Length > 0 && name[0].IsDigit)
		{
			_writer.Write("_");
		}
		else
		{
			for (let kw in KEYWORDS)
			{
				if (kw == name)
				{
					_writer.Write("@");
					break;
				}
			}
		}
		
		_writer.Write(name);
	}


	void WriteBeefType(Parser.TypeRef type, String buffer)
	{
		StringStream ss = scope .(buffer, .Reference);
		ss.Position = buffer.Length;
		StreamWriter writer = scope .(ss, System.Text.Encoding.UTF8, 64);
		using(SetRestore<StreamWriter>(ref _writer, writer))
		{
			WriteBeefType(type);
		}
	}

	void WriteBeefType(Parser.TypeRef type)
	{
		int32 ptr = type.ptrDepth;

		if (type.typeString.IsEmpty)
		{
			if (let fnDecl = type.typeDef as Parser.FunctionTypeDef)
			{
				GenerateFunction(fnDecl, true);
			}
			else
				Runtime.FatalError();
		}
		else
		{
			_writer.Write(type.typeString);
		}

		if (type.sizedArray != null)
		{
			for (let dimm in type.sizedArray)
				_writer.Write($"[{dimm}]");
		}

		if (_handleTypes.Contains(type.typeString))
			ptr--;

		Runtime.Assert(ptr >= 0);
		for (int32 _ < ptr)
			_writer.Write("*");
	}

	Result<void> GetEnumTypeInfo(Parser.EnumDef e, String prefix, out bool hasDupes)
	{
		hasDupes = false;

		HashSet<int64> dupes = scope .(e.values.Count);
		for (let v in e.values)
		{
			if (!dupes.Add(v.value))
			{
				hasDupes = true;
				break;
			}	
		}

		FIND_PREFIX:
		do
		{
			if (_settings.enumGenerateFlags & .RemovePrefix != .RemovePrefix)
				break FIND_PREFIX;

			if (e.values.Count < 2)
				break FIND_PREFIX;

			int shortestLength = int.MaxValue;
			StringView name = default;

			for (let v in e.values)
			{
				if (v.name.Length < shortestLength)
				{
					shortestLength = v.name.Length;
					name = v.name;
				}
			}

			if (shortestLength == int.MaxValue)
				break FIND_PREFIX;

			while (name.Length > 0)
			{
				CHECK_PREFIX:
				do
				{
					for (let v in e.values)
					{
						if (!v.name.StartsWith(name))
							break CHECK_PREFIX;
					}
					prefix.Set(name);
					break FIND_PREFIX;
				}
				
				name.RemoveFromEnd(1);
			}
		}
		

		return .Ok;
	}

	void GenerateEnum(Parser.EnumDef e)
	{
		String baseType = "c_int";

		if (e.baseType != null)
		{
			Runtime.NotImplemented();
		}

		String valueNamePrefix = scope .();
		GetEnumTypeInfo(e, valueNamePrefix, let hasDupes);
		
		List<String> attrs = scope .(4);
		if (hasDupes)
			attrs.Add("AllowDuplicates");
		WriteAttrs(attrs);

		WriteIndent();
		WriteProtection(.Public);
		_writer.Write($"enum ");
		WriteName(e.name);
		_writer.WriteLine($" : {baseType}");

		WriteIndent();
		_writer.WriteLine("{");

		PushIndent();

		int64 next = 0;
		String tmp = scope .(32);
		for (let v in e.values)
		{
			WriteIndent();
			WriteIdentifier(v.name.Substring(valueNamePrefix.Length));
			if ((_settings.enumGenerateFlags & .OmitImplicitValues != .OmitImplicitValues) || next != v.value)
			{
				_writer.Write(" = ");
				_writer.Write(v.value.ToString(.. tmp..Clear()));
			}
			_writer.WriteLine(",");
			next = v.value + 1;
		}
		PopIndent();

		WriteIndent();
		WriteEnd("}");

	}

	int WriteBitfield(Span<Parser.VariableDecl> fields)
	{
		int32 prevSize = fields[0].type.size;
		int32 bits = prevSize * 8;

		String attr = scope .(64);

		int i;
		for (i = 0; i < fields.Length; i++)
		{
			let f = fields[i];

			if (f.type.bitWidth == -1)
				break;

			if (f.type.size != prevSize)
				break;

			bits -= f.type.bitWidth;
			if (bits < 0)
			{
				break;
			}

			attr..Clear()..AppendF($"Bitfield(.Public, .Bits({f.type.bitWidth}), \"");
			WriteIdentifier(f.name, attr);
			attr.Append("\")");

			WriteAttrs(Span<String>(&attr, 1), false);

			if (bits == 0)
				break;	
		}

		return Math.Max(i - 1, 0);
	}

	void GenerateStruct(Parser.StructTypeDef s)
	{
		Runtime.Assert(s.tag == .Union || s.tag == .Struct);

		List<String> attrs = scope .(4);

		attrs.Add("CRepr");
		if (s.tag == .Union)
			attrs.Add("Union");

		WriteAttrs(attrs);
		WriteIndent();
		WriteProtection(.Public);
		_writer.Write($"struct ");
		WriteName(s.name);
		_writer.WriteLine();
		WriteIndent();
		_writer.WriteLine("{");

		PushIndent();

		let sr_using = SetRestore<bool>(ref forceUsing, false);
		defer sr_using.Dispose();
		
		if (s.innerTypes != null)
		{
			for (let innerType in s.innerTypes)
			{
				if (innerType.flags.HasFlag(.Field))
					continue;

				GenerateType(innerType.typedef, _writer);
			}
		}

		Result<Parser.StructTypeDef.InnerType> GetInnerType(Parser.TypeDef type)
		{
			if (type == null || s.innerTypes == null)
				return .Err;

			for (let innerType in s.innerTypes)
			{
				if (innerType.typedef == type)
					return innerType;
			}

			return .Err;
		}

		let count = s.fields.Count;
		for (int i = 0; i < count; ++i)
		{
			let f = s.fields[i];
			if (GetInnerType(f.typedef) case .Ok(let innerType))
			{
				using(SetRestore<bool>(ref this.skipEndl, true))
				{
					using(SetRestore<bool>(ref this.skipNames, true))
					{
						bool needsUsing = false;
						if (innerType.flags.HasFlag(.Anon))
							needsUsing  = true;

						using (SetRestore<bool>(ref forceUsing, needsUsing))
						{
							GenerateType(f.typedef, _writer);
						}
					}
				}
			}
			else
			{
				EProtectionKind protection = .Public;
				if (f.type.bitWidth > 0)
				{
					protection = .Private;
					i += WriteBitfield(s.fields.GetRange(i));
					f.name..Clear()..AppendF($"__bitfield_{i}__");
				}

				WriteIndent();
				WriteProtection(protection);
				WriteBeefType(f.type);
			}

			_writer.Write(" ");
			WriteIdentifier(f.name);
			if (f.typedef != null)
			{
				int j;
				for (j = i + 1; j < count; ++j)
				{
					if (s.fields[j].typedef != f.typedef)
					{
						j--;
						break;
					}

					_writer.Write(", ");
					WriteIdentifier(f.name);
				}
				i = j;
			}
			_writer.WriteLine(";");
		}

		PopIndent();
		WriteIndent();
		WriteEnd("}");
	}

	void GenerateFunction(Parser.FunctionTypeDef f, bool isInline = false)
	{
		Runtime.Assert((isInline && f.typeOnly) || !isInline);

		List<String> attrs = scope .(4);
		if (!f.typeOnly)
			attrs.Add("CLink");

		var callconv = f.callConv;
		if (callconv == .Unspecified)
			callconv = .Cdecl;

		attrs.Add(scope $"CallingConvention(.{callconv})");
		if (!isInline)
		{
			WriteAttrs(attrs);
			WriteIndent();
		}

		if (f.typeOnly)
		{
			if (!isInline)
				WriteProtection(.Public);
			_writer.Write("function ");

			if (isInline)
			{
				WriteAttrs(attrs, true);
				_writer.Write(" ");
			}	
		}
		else
		{
			WriteProtection(.Public);
			_writer.Write("static extern ");
		}
		WriteBeefType(f.resultType);
		_writer.Write($" {f.name}(");

		for (let a in f.args)
		{
			if (@a.Index != 0)
				_writer.Write(", ");

			WriteBeefType(a.type);
			if (a.name.Length > 0)
			{
				_writer.Write(" ");
				WriteIdentifier(a.name);
			}
		}

		if (f.isVarArg)
		{
			if (f.args.Count > 0)
				_writer.Write(", ");
			_writer.Write("...");
		}	

		_writer.Write(")");
		if (!isInline)
			WriteEnd(";");
	}

	void GenerateAlias(Parser.TypeAliasDef f)
	{
		WriteProtection(.Public);
		_writer.Write($"typealias {f.name} = ");
		WriteBeefType(f.alias);
		_writer.WriteLine(";");
	}

	void GenerateAliasFiltered(Parser.TypeAliasDef def)
	{
		if ((def.flags & .ForceGenerate) != .ForceGenerate)
		{
			/*if ((def.flags & (.Resolved) !=  .Resolved))
				continue;*/

			if ((def.flags & (.Primitive) == .Primitive) && (def.alias.ptrDepth == 0 && def.alias.sizedArray == null))
				return;
		}

		if (def.flags & .Function == .Function)
		{
			if (let fn = def.alias.typeDef as Parser.FunctionTypeDef)
			{
				fn.name.Set(def.name);
				GenerateFunction(fn);
			}
			else
			{
				_writer.Write($"typealias {def.name} = ");
				WriteBeefType(def.alias);
				_writer.WriteLine(";");
			}
			return;
		}

		if (def.flags.HasFlag(.Struct))
		{
			let exists = _parser.types.TryGetValue(def.name, let type);

			if (def.name == def.alias.typeString)
			{
				if (!exists || (type is Parser.TypeAliasDef))
				{
					if (_settings.intHandles)
					{
						_handleTypes.Add(type.name);
						_writer.WriteLine($"struct {def.name} : int {{ }}");
					}
					else
					{
						_writer.WriteLine($"struct {def.name};");
					}
				}
			}
			else
			{
				let exists2 = _parser.types.ContainsKeyAlt(def.alias.typeString);

				if (!exists2)
				{
					_writer.WriteLine($"struct {def.alias.typeString};");
				}
				
				GenerateAlias(def);
			}
			return;
		}

		if (def.flags & (.Enum | .Struct | .Function) == 0)
		{
			GenerateAlias(def);
		}
	}

	void GenerateType(Parser.TypeDef type, StreamWriter writer)
	{
		if (let structDef = type as Parser.StructTypeDef)
		{
			GenerateStruct(structDef);
			return;
		}

		if (let enumDef = type as Parser.EnumDef)
		{
			GenerateEnum(enumDef);
			return;
		}

		if (let fnDef = type as Parser.FunctionTypeDef)
		{
			GenerateFunction(fnDef, false);
			return;
		}	
	}

	public void Generate(Parser parser, Settings settings)
	{
		_parser = parser;
		_settings = settings;

		Stream stream = settings.outStream;
		if (stream == null)
		{
			Runtime.Assert(settings.OutFilepath.Length > 0);
			let directoryPath = scope String();
			if (Path.GetDirectoryPath(settings.OutFilepath, directoryPath) case .Ok)
			{
				if (Directory.CreateDirectory(directoryPath) case .Err(let err) && err != .AlreadyExists)
					Log.Error(scope $"Failed to create output directory '{directoryPath}' ({err})");
			}


			FileStream fs = scope:: .();
			fs.Open(settings.OutFilepath, .Create, .Write, .ReadWrite);
			stream = fs;
		}

		_writer = scope .(stream, System.Text.UTF8Encoding.UTF8, 4096);

		_writer.WriteLine("using System;");
		_writer.WriteLine("using System.Interop;");
		_writer.WriteLine();
		_writer.WriteLine($"namespace {settings.Namespace};");
		_writer.WriteLine();

		{
			let startPos = stream.Position;
			defer
			{
				if (startPos != stream.Position)
					_writer.WriteLine();
			}
			for (let kv in parser.aliasMap)
			{
				GenerateAliasFiltered(kv.value);
			}
		}
		

		for (let e in parser.enums)
		{
			GenerateEnum(e);
			_writer.WriteLine();
		}

		for (let s in parser.structs)
		{
			GenerateStruct(s);
			_writer.WriteLine();
		}

		_writer.WriteLine("public static");
		_writer.WriteLine("{");
		PushIndent();

		{
			let startPos = stream.Position;
			defer
			{
				if (startPos != stream.Position)
					_writer.WriteLine();
			}

			PreprocessorEvaluator evaluator = scope PreprocessorEvaluator(_parser);
			evaluator..EvalAll((macro) => {
				return !macro.IsFnLike && !macro.isFiltered && !macro.invalid;
			})..ForEach((macroEval) => {

				WriteIndent();
				_writer.Write("public const ");
				_writer.Write(macroEval.type.AsString);
				_writer.Write(" ");
				WriteIdentifier(macroEval.macro.name);
				_writer.WriteLine($" = {macroEval.expanded};");
			});
		}

		{
			let startPos = stream.Position;
			defer
			{
				if (startPos != stream.Position)
					_writer.WriteLine();
			}

			for (let v in parser.globalVars)
			{
				List<String> attrs = scope .(4);

				switch (v.storageKind)
				{
				case .Extern:
					{
						attrs.Add("CLink");
						WriteAttrs(attrs);
						WriteIndent();
						WriteProtection(.Public);
						_writer.Write("static extern ");
						WriteBeefType(v.type);
						_writer.WriteLine($" {v.name};");
					}

				case .Static:
					{

					}

				case .Unknown:
					{
						Runtime.NotImplemented();
					}
				}
			}
		}

		for (let f in parser.functions)
 		{
			 if (f.linkageType != .External)
				 continue;

			 GenerateFunction(f);
			 _writer.WriteLine();
		}

		PopIndent();
		WriteEnd("}");

		_writer.WriteLine();
	}
}