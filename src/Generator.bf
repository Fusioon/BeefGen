using System;
using System.IO;
using System.Collections;
using System.Interop;

namespace BeefGen;

class Generator
{
	const String INDENT_STR = "\t";
	append String _indent;

	String[?] KEYWORDS = .("internal", "function", "delegate", "where",
							"operator", "class", "struct", "extern",
							"for", "while", "do", "repeat", "abstract",
							"base", "virtual", "override", "extension",
							"namespace", "using", "out", "in", "ref");

	Parser _parser;

	append HashSet<String> _createdTypes;

	void PushIndent()
	{
		_indent.Append(INDENT_STR);
	}

	void PopIndent()
	{
		_indent.RemoveFromEnd(INDENT_STR.Length);
	}

	void WriteIndent(StreamWriter writer)
	{
		writer.Write(_indent);
	}

	void WriteAttrs(Span<String> attrs, StreamWriter writer, bool _inline = false)
	{
		const String ATTR_SUFFIX = nameof(Attribute);

		if (attrs.Length > 0)
		{
			if (!_inline)
				WriteIndent(writer);

			writer.Write("[");
			for (let a in attrs)
			{
				if (@a.Index != 0)
					writer.Write(", ");

				StringView attrView = a;

				if (attrView.EndsWith(ATTR_SUFFIX))
					attrView.RemoveFromEnd(ATTR_SUFFIX.Length);

				writer.Write(attrView);
			}

			writer.Write("]");
			if (!_inline)
				writer.WriteLine();
		}
	}

	void WriteIdentifier(StringView name, StreamWriter writer)
	{
		for (let kw in KEYWORDS)
		{
			if (kw == name)
			{
				writer.Write("@");
				break;
			}
		}
		writer.Write(name);
	}

	void WriteBeefType(Parser.TypeRef type, String buffer)
	{
		StringStream ss = scope .(buffer, .Reference);
		ss.Position = buffer.Length;
		StreamWriter writer = scope .(ss, System.Text.Encoding.UTF8, 64);
		WriteBeefType(type, writer);
	}

	void WriteBeefType(Parser.TypeRef type, StreamWriter writer)
	{
		if (type.typeString.IsEmpty)
		{
			if (let fnDecl = type.typeDef as Parser.FunctionTypeDef)
			{
				GenerateFunction(fnDecl, writer, true);
				return;
			}
			else
				Runtime.FatalError();
		}

		writer.Write(type.typeString);

		if (type.sizedArray != null)
		{
			for (let dimm in type.sizedArray)
				writer.Write($"[{dimm}]");
		}

		for (int32 _ in 0..<type.ptrDepth)
			writer.Write("*");
	}

	Result<void> GetEnumTypeInfo(Parser.EnumDef e, String prefix, out bool hasDupes)
	{
		hasDupes = false;

		HashSet<String> dups = scope .(e.values.Count);
		for (let v in e.values)
		{
			if (v.value.Length > 0 && !dups.Add(v.value))
			{
				hasDupes = true;
				break;
			}	
		}

		return .Ok;
	}

	void GenerateEnum(Parser.EnumDef e, StreamWriter writer)
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
		WriteAttrs(attrs, writer);

		WriteIndent(writer);
		writer.WriteLine($"public enum {e.name} : {baseType}");
		WriteIndent(writer);
		writer.WriteLine("{");

		PushIndent();
		for (let v in e.values)
		{
			WriteIndent(writer);
			WriteIdentifier(v.name, writer);
			if (v.value.Length > 0)
			{
				writer.Write(" = ");
				writer.Write(v.value);
			}
			writer.WriteLine(",");
		}
		PopIndent();

		WriteIndent(writer);
		writer.WriteLine("}");

		_createdTypes.Add(e.name);
	}

	void GenerateStruct(Parser.StructTypeDef s, StreamWriter writer)
	{
		Runtime.Assert(s.tag == .Union || s.tag == .Struct);

		List<String> attrs = scope .(4);

		if (s.name == "crypto_hash_sha512_state")
			NOP!();

		attrs.Add("CRepr");
		if (s.tag == .Union)
			attrs.Add("Union");

		WriteAttrs(attrs, writer);
		WriteIndent(writer);
		writer.WriteLine($"public struct {s.name}");
		WriteIndent(writer);
		writer.WriteLine("{");

		PushIndent();

		if (s.innerTypes != null)
		{
			for (let t in s.innerTypes)
			{
				if (let sDef = t as Parser.StructTypeDef)
					GenerateStruct(sDef, writer);
			}
		}

		for (let f in s.fields)
		{
			WriteIndent(writer);
			writer.Write("public ");
			WriteBeefType(f.type, writer);
			writer.Write(" ");
			WriteIdentifier(f.name, writer);
			writer.WriteLine(";");
		}
		PopIndent();
		WriteIndent(writer);
		writer.WriteLine("}");

		_createdTypes.Add(s.name);
	}

	void GenerateFunction(Parser.FunctionTypeDef f, StreamWriter writer, bool isInline = false)
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
			WriteAttrs(attrs, writer);
			WriteIndent(writer);
		}

		if (f.typeOnly)
		{
			if (!isInline)
				writer.Write("public ");
			writer.Write("function ");

			if (isInline)
			{
				WriteAttrs(attrs, writer, true);
				writer.Write(" ");
			}	
		}
		else
		{
			writer.Write("public static extern ");
		}
		WriteBeefType(f.resultType, writer);
		writer.Write($" {f.name}(");

		for (let a in f.args)
		{
			if (@a.Index != 0)
				writer.Write(", ");

			WriteBeefType(a.type, writer);
			writer.Write(" ");
			WriteIdentifier(a.name, writer);
		}

		if (f.isVarArg)
		{
			if (f.args.Count > 0)
				writer.Write(", ");
			writer.Write("...");
		}	

		writer.Write(")");
		if (!isInline)
			writer.WriteLine(";");
	}

	void GenerateAlias(Parser.TypeAliasDef f, StreamWriter writer)
	{
		writer.Write($"public typealias {f.name} = ");
		WriteBeefType(f.alias, writer);
		writer.WriteLine(";");
	}

	public void Generate(Parser parser, Settings settings)
	{
		_parser = parser;

		Stream stream = settings.outStream;
		if (stream == null)
		{
			FileStream fs = scope:: .();
			fs.Open(settings.OutFilepath, .Create, .Write);
			stream = fs;
		}

		StreamWriter sw = scope .(stream, System.Text.UTF8Encoding.UTF8, 4096);

		sw.WriteLine("using System;");
		sw.WriteLine("using System.Interop;");
		sw.WriteLine();
		sw.WriteLine($"namespace {settings.Namespace};");
		sw.WriteLine();

		for (let e in parser.enums)
		{
			GenerateEnum(e, sw);
			sw.WriteLine();
		}

		for (let s in parser.structs)
		{
			GenerateStruct(s, sw);
			sw.WriteLine();
		}

		sw.WriteLine("public static");
		sw.WriteLine("{");
		PushIndent();
		{
			let startPos = stream.Position;
			defer
			{
				if (startPos != stream.Position)
					sw.WriteLine();
			}

			for (let v in parser.globalVars)
			{
				List<String> attrs = scope .(4);

				switch (v.storageKind)
				{
				case .Extern:
					{
						attrs.Add("CLink");
						WriteAttrs(attrs, sw);
						WriteIndent(sw);
						sw.Write("public static extern ");
						WriteBeefType(v.type, sw);
						sw.WriteLine($" {v.name};");
					}

				case .Unknown:
					{

					}
				}
			}
		}

		for (let f in parser.functions)
 		{
			 if (f.linkageType != .External)
				 continue;

			 GenerateFunction(f, sw);
			 sw.WriteLine();
		}

		PopIndent();
		sw.WriteLine("}");

		sw.WriteLine();

		for (let kv in parser.aliasMap)
		{
			let def = kv.value;

			if ((def.flags & .ForceGenerate) != .ForceGenerate)
			{
				/*if ((def.flags & (.Resolved) !=  .Resolved))
					continue;*/

				if ((def.flags & (.Primitive) == .Primitive) && (def.alias.ptrDepth == 0 && def.alias.sizedArray == null))
					continue;
			}
			else
				NOP!();

			if (def.flags & .Function == .Function)
			{
				if (let fn = def.alias.typeDef as Parser.FunctionTypeDef)
				{
					fn.name.Set(def.name);
					GenerateFunction(fn, sw);
				}
				else
				{
					sw.Write($"typealias {def.name} = ");
					WriteBeefType(def.alias, sw);
					sw.WriteLine(";");
				}
				continue;
			}

			if (def.flags.HasFlag(.Struct))
			{
				let created = _createdTypes.ContainsAlt(def.name);

				if (def.name == def.alias.typeString)
				{
					if (!created)
						sw.WriteLine($"struct {def.name};");
				}
				else
				{
					let createdAlias = _createdTypes.ContainsAlt(def.alias.typeString);

					if (!createdAlias)
					{
						sw.WriteLine($"struct {def.alias.typeString};");
					}
					
					sw.Write($"typealias {def.name} = ");
					WriteBeefType(def.alias, sw);
					sw.WriteLine(";");
				}

				continue;
			}

			if (def.flags & (.Enum | .Struct | .Function) == 0)
			{
				GenerateAlias(def, sw);
			}

		}
	}
}