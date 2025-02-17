using System;
using System.IO;
using System.Collections;
using libclang_beef;

namespace BeefGen;

class Program
{
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

	public static void Main()
	{
		Log.Init(true, true);

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
	}
}