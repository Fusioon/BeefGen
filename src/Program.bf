using System;

using System.IO;
using System.Collections;
using libclang_beef;

namespace BeefGen;

class Program
{
	static String HELP_STRING =
		"""
		BeefGen - Generate BeefLang bindings from C header files

		Example usage:
		  beefgen --std=c23 --namespace=TestCLI --f-path=*include/*.h --input=include/test.h --out="src/Generated/Test CLI.bf"

		  --help                  Show help message and exit
		  --std=<value>           Language standard to compile for
		  --namespace=<value>     Name of the namespace in the generated beef file
		  --inthandles            Generate int structs instead of opaque type pointers
		  --enum-no-prefix        Remove common value name prefix
		  --enum-all-values       Force generation of all enum values
		  --out=<path>            Path to the output file
		  --input=<path>          Add <path> to the input files
		  --incdir=<path>         Add <path> to include search path
		  --def=<macro>           Define <macro> to 1
		  --undef=<macro>         Undefine <macro>
		  --f-path=<pattern>      Filter by input file path (supports *, ?)
		  --f-typename=<pattern>  Filter by type name (supports *, ?)

		Filters can be set multple times and data will be generated when any
		  filter from the group matches, so if both path and typename filter
		  is used the data must pass both filters to be generated

		Patterns supports `*` (match any) and `?` (match one) wildcards
		  for directory separators use `/` this will match `\\` and `/`

		""";

	static void Generate(Settings settings, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
	{
		Parser parser = scope .();
		switch (parser.Parse(settings))
		{
		case .Ok:
			{
				Generator gen = scope .();
				gen.Generate(parser, settings);
			}
		case .Err:
			{
				Log.Error(scope $"Parsing failed", CallerPath, CallerName, CallerLine);
			}
		}
	}

	static (StringView, StringView) SplitArg(StringView a)
	{
		let idx = a.IndexOf('=');
		if (idx == -1)
			return (a, default);

		return (a.Substring(0, idx), a.Substring(idx + 1));
	}

	static void RunCLI(String[] args)
	{
		Settings settings = scope .();
		settings.enumGenerateFlags = .OmitImplicitValues;

		List<String> pathFilters = scope .();
		List<String> typenameFilters = scope .();

		defer
		{
			ClearAndDeleteItems!(typenameFilters);
			ClearAndDeleteItems!(pathFilters);
		}

		for (let a in args)
		{
			(let cmd, let val) = SplitArg(a);
			switch (cmd)
			{
			case "--help":
				{
					Console.WriteLine(HELP_STRING);
					return;
				}
			case "--std":
				settings.LangStandard = val;
			case "--namespace":
				settings.Namespace = val;
			case "--inthandles":
				settings.intHandles = true;
			case "enum-no-prefix":
				settings.enumGenerateFlags |= .RemovePrefix;
			case "--enum-all-values":
				settings.enumGenerateFlags &= ~(.OmitImplicitValues);
			case "--out":
				settings.OutFilepath = val;
			case "--input":
				settings.AddInputFile(val);
			case "--incdir":
				settings.AddIncludeDir(val);
			case "--def":
				settings.AddPreprocessorDefinition(val);
			case "--undef":
				settings.AddPreprocessorUndefine(val);
			case "--f-path":
				{
					pathFilters.Add(new .(val));
				}
			case "--f-typename":
				{
					typenameFilters.Add(new .(val));
				}
			default:
				{
					Log.Warning(scope $"Unused argument: '{a}'");
				}
			}
		}

		const bool IGNORE_CASE = true;

		settings.typeFilter = new (typename, kind, source) =>
			{
				CHECK_PATHS:
				do
				{
					if (pathFilters.IsEmpty)
						break CHECK_PATHS;

					for (let filter in pathFilters)
					{
						if (source.path.Match(filter, IGNORE_CASE, true))
							break CHECK_PATHS;
					}

					return false;
				}

				CHECK_TYPENAME:
				do
				{
					if (typenameFilters.IsEmpty)
						break CHECK_TYPENAME;

					for (let filter in typenameFilters)
					{
						if (typename.Match(filter, IGNORE_CASE))
							break CHECK_TYPENAME;
					}

					return false;
				}

				return true;
			};

		Generate(settings);
	}

	static void RunNonCLI()
	{
#if DEBUG
		let dir = Directory.GetCurrentDirectory(.. scope .());
		{
			Settings settings = scope .()
				{
					LangStandard = "c23", // Which language standard to use (c2y, c23, c17, c11, c99, c89)
					Namespace = "Test", // Name of the namespace in the generated beef file
					typeFilter = new (typename, kind, source) =>
						{
						// return value indicates if the type/function/constant should be present in the generated beef file
							return source.path.Contains("include");
						},
					OutFilepath = "src/Generated/Test.bf", // Name of the output file
					outStream = null, // or you can use stream

					intHandles = true, // Generate int structs `struct ExampleIntStruct : int {}` instead of opaque type pointers `struct ExampleOpaque;`
					enumGenerateFlags = .RemovePrefix | .OmitImplicitValues
				};
			settings.AddInputFileF($"{dir}/include/test.h"); // Add file to generate binding from
			settings.AddIncludeDirF($"{dir}/include"); // Add directory to include search path

			settings.AddPreprocessorDefinition("GEN_TEST_DEFINED");
			settings.AddPreprocessorDefinition("GEN_TEST_FORCEUNDEF");
			settings.AddPreprocessorUndefine("GEN_TEST_FORCEUNDEF");
			Generate(settings);
		}
#endif
	}

	public static void Main(String[] args)
	{
		Log.Init(true, true);
		if (args.Count > 0)
			RunCLI(args);
		else
			RunNonCLI();
	}
}