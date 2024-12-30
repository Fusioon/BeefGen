using System;
using System.IO;
using System.Collections;
using libclang_beef;

namespace BeefGen;

class Program
{
	public static void Main()
	{
		Log.Init(true, true);

		let dir = Directory.GetCurrentDirectory(.. scope .());

		/*Settings settings = scope .();
		settings.Namespace = "Sodium";
		settings.AddInputFileF($"{dir}/include/SODIUM_include/sodium.h");
		settings.AddIncludeDirF($"{dir}/include/SODIUM_include");
		settings.typeFilter = new (typename, kind, source) => {
			return source.path.Contains("include/SODIUM_include");
		};
		settings.OutFilepath = "src/Sodium.bf";*/

		Settings settings = scope .();
		settings.Namespace = "SDL3";
		settings.AddInputFileF($"{dir}/include/SDL_include/SDL3/SDL.h");
		settings.AddIncludeDirF($"{dir}/include/SDL_include");
		settings.typeFilter = new (typename, kind, source) => {
			return source.path.Contains("include/SDL_include");
		};
		settings.OutFilepath = "src/SDL3.bf";

		Parser parser = scope .();
		if (parser.Parse(settings) case .Ok)
		{
			Generator gen = scope .();
			gen.Generate(parser, settings);
		}
	}
}