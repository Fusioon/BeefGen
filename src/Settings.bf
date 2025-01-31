using System;
using System.Collections;
using System.IO;

namespace BeefGen;

struct SourceInfo : this(StringView inputFile, StringView path, int line, int col, int offset);

enum EDeclKind
{
	Enum,
	Struct,
	Function,
	Typedef,
	Variable,
	Macro
}

enum EEnumGenerateFlags
{
	None = 0x00,
	/// Skips assignment of enum values which are implicitly known (incremented by one from previous value)
	OmitImplicitValues = 0x01,
	/// Automatically detects common value name prefix and removes it
	RemovePrefix = 0x02,
	/// Transform uppercase / underscore (_) value names into capitalized versions
	//TransformCase = 0x04
}

public class Settings
{
	public delegate bool TypeFilterDelegate(StringView typename, EDeclKind kind, SourceInfo source);
	internal append List<String> _includeDirs ~ ClearAndDeleteItems!(_);
	internal append List<String> _inputFiles ~ ClearAndDeleteItems!(_);
	internal append List<String> _commandLineArgs ~ ClearAndDeleteItems!(_);
	internal append List<String> _preprocDefines ~ ClearAndDeleteItems!(_);
	internal append List<String> _preprocUndefines ~ ClearAndDeleteItems!(_);
	internal append String _outputNamespace;

	internal append String _langStd;

	append String _outFilepath;
	public Stream outStream;

	public TypeFilterDelegate typeFilter ~ delete _;

	// Add directory to include search path
	public void AddIncludeDir(StringView path) => _includeDirs.Add(new .(path));
	public void AddIncludeDirF(StringView format, params Span<Object> args) => _includeDirs.Add(new String()..AppendF(format, params args));

	// Add file to generate bindings from
	public void AddInputFile(StringView path) => _inputFiles.Add(new .(path));
	public void AddInputFileF(StringView format, params Span<Object> args) => _inputFiles.Add(new String()..AppendF(format, params args));

	// Add custom command line options when invoking clang
	public void AddCommandLineArg(StringView arg) => _commandLineArgs.Add(new .(arg));
	public void AddCommandLineArgF(StringView format, params Span<Object> args) => _commandLineArgs.Add(new String()..AppendF(format, params args));

	// Define macro
	public void AddPreprocessorDefinition(StringView def) => _preprocDefines.Add(new .(def));

	// Undefine macro
	public void AddPreprocessorUndefine(StringView undef) => _preprocUndefines.Add(new .(undef));

	public StringView Namespace
	{
		get => _outputNamespace;
		set => _outputNamespace.Set(value);
	}

	public StringView OutFilepath
	{
		get => _outFilepath;
		set => _outFilepath.Set(value);
	}

	public StringView LangStandard
	{
		get => _langStd;
		set => _langStd.Set(value);
	}

	public EEnumGenerateFlags enumGenerateFlags = .OmitImplicitValues;
	// Generate int structs instead of opaque type pointers
	public bool intHandles = true;
}
