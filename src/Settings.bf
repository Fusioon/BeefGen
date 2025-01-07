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

	public void AddIncludeDir(StringView path) => _includeDirs.Add(new .(path));
	public void AddIncludeDirF(StringView format, params Span<Object> args) => _includeDirs.Add(new String()..AppendF(format, params args));

	public void AddInputFile(StringView path) => _inputFiles.Add(new .(path));
	public void AddInputFileF(StringView format, params Span<Object> args) => _inputFiles.Add(new String()..AppendF(format, params args));

	public void AddCommandLineArg(StringView arg) => _commandLineArgs.Add(new .(arg));
	public void AddCommandLineArgF(StringView format, params Span<Object> args) => _commandLineArgs.Add(new String()..AppendF(format, params args));

	public void AddPreprocessorDefinition(StringView def) => _preprocDefines.Add(new .(def));
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

}
