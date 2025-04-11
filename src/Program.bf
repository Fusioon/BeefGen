using System;
using System.IO;
using System.Collections;
using libclang_beef;

namespace BeefGen;

class Program
{
	static String HELP_STRING =
"""
	--std=<>
	--namespace=<>
	--inthandles
	--enum-remove-prefix
	--enum-force-all-values
	--out=<>
	--input=<>
	--incdir=<>
	--def=<>
	--undef=<>
	--filter=<>
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

	static bool StringMatch(StringView str, StringView pattern, bool ignoreCase = true)
	{
		// * match zero or more
		// ? match one

		let length = Math.Min(str.Length, pattern.Length);

		int lastWildcard = 0;
		for (int i = 0; i < length; i++)
		{
			let c = pattern[i];

			if (c == '*' && i > 0)
			{
				StringView subPattern = pattern.Substring(lastWildcard, i - lastWildcard);
				StringView subStr = str.Substring(0);

				if (StringMatch(subStr, subPattern, ignoreCase) == false)
					return false;

				lastWildcard = i + 1;
			}
			else if (c == '?')
			{

			}
			else
			{
				let strC = str[i];
				if ((c == strC) || (ignoreCase && c.ToLower == strC.ToLower))
				{
					NOP!();
				}
				else
					return false;
			}
		}

		// @TODO
		return true;
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
			case "--enum-remove-prefix":
				settings.enumGenerateFlags |= .RemovePrefix;
			case "--enum-force-all-values":
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
			case "--filter-path":
				{
					pathFilters.Add(new .(val));
				}
			case "--filter-typename":
				{
					typenameFilters.Add(new .(val));
				}
			}
		}

		settings.typeFilter = new (typename, kind, source) => {

			CHECK_PATHS:
			do
			{
				if (pathFilters.IsEmpty)
					break CHECK_PATHS;

				for (let filter in pathFilters)
				{
					if (StringMatch(source.path, filter))
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
					if (StringMatch(typename, filter))
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
				typeFilter = new (typename, kind, source) => {
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

		{
			Settings settings = scope .()
			{
				LangStandard = "c23", // Which language standard to use (c2y, c23, c17, c11, c99, c89)
				Namespace = "SDL3", // Name of the namespace in the generated beef file
				typeFilter = new (typename, kind, source) => {
					// return value indicates if the type/function/constant should be present in the generated beef file
				  	return source.path.Contains("SDL3");
				},
				OutFilepath = "src/Generated/SDL3.bf", // Name of the output file
				outStream = null, // or you can use stream

				intHandles = true, // Generate int structs `struct ExampleIntStruct : int {}` instead of opaque type pointers `struct ExampleOpaque;`
				enumGenerateFlags = .RemovePrefix | .OmitImplicitValues
			};
			settings.AddInputFileF(@"H:\SDL\include\SDL3\SDL.h"); // Add file to generate binding from
			settings.AddIncludeDirF(@"H:\SDL\include"); // Add directory to include search path
			
			Generate(settings);
		}
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