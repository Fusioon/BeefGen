using System;
namespace BeefGen;


public enum ELogLevel
{
	case Trace,
	Info,
	Success,
	Warning,
	Error,
	Fatal;

	public ConsoleColor ConsoleColor
	{
		[Inline]
		get
		{
			switch (this)
			{
			case .Trace:
				return .Gray;
			case .Info:
				return .White;
			case .Success:
				return .Green;
			case .Warning:
				return .Yellow;
			case .Error:
				return .Red;
			case .Fatal:
				return .Magenta;
			}
		}
	}

	public String ColorCodeStr
	{
		[Inline]
		get
		{
			switch (this)
			{
			case .Trace:
				return "\x01\x5F\x5F\x5F\x7F";
			case .Info:
				return "\x01\x7F\x7F\x7F\x7F";
			case .Success:
				return "\x01\x20\x7F\x20\x7F";
			case .Warning:
				return "\x01\x20\x7F\x7F\x7F";
			case .Error:
				return "\x01\x20\x20\x7F\x7F";
			case .Fatal:
				return "\x01\x7F\x30\x7F\x7F";
			}
		}
	}

	public String Prefix
	{
		[Inline]
		get
		{
			switch (this)
			{
			case .Trace: return "[TRACE]";
			case .Info: return "";
			case .Success: return "[SUCCESS]";
			case .Warning: return "[WARN]";
			case .Error: return "[ERROR]";
			case .Fatal: return "[FATAL]";
			}
		}
	}
}

public delegate void LogCallback(ELogLevel level, DateTime time, StringView message, StringView preferredFormat);

public static class Log
{
	public static ELogLevel LogLevel = .Trace;
	public static ELogLevel LogCallerPathMinLevel = .Error;

	internal static void Init()
	{
		// This doesn't handle Runtime.FatalError :(
		Runtime.AddErrorHandler(new (stage, error) => {

			if (stage == .PreFail)
				return .ContinueFailure;

			if (let fatalErr = error as Runtime.FatalError)
			{
				Log.Error(fatalErr.mError);
			}
			if (let assertErr = error as Runtime.AssertError)
			{
				Log.Error(scope $"Assert failed: '{assertErr.mError}'", assertErr.mFilePath, "", assertErr.mLineNum);
			}
			if (let loadLibError = error as Runtime.LoadSharedLibraryError)
			{
				Log.Error(scope $"Failed to load shared library '{loadLibError.mPath}'");
			}
			if (let getProcAddrError = error as Runtime.GetSharedProcAddressError)
			{
				Log.Error(scope $"Failed to load address of '{getProcAddrError.mProcName}' in {getProcAddrError.mPath}");
			}

			return .ContinueFailure;
		});
	}


	private static Event<LogCallback> _callbacks ~ _.Dispose();

	public static void AddCallback(LogCallback cb)
	{
		_callbacks.Add(cb);
	}
	public static bool RemoveCallback(LogCallback cb)
	{
		return _callbacks.Remove(cb) case .Ok;
	}

	[Inline] public static void Trace(StringView message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Trace, message, CallerPath, CallerName, CallerLine);
	[Inline] public static void Info(StringView message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Info, message, CallerPath, CallerName, CallerLine);
	[Inline] public static void Success(StringView message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Success, message, CallerPath, CallerName, CallerLine);
	[Inline] public static void Warning(StringView message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Warning, message, CallerPath, CallerName, CallerLine);
	[Inline] public static void Error(StringView message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Error, message, CallerPath, CallerName, CallerLine);

	[Inline] public static void Trace(String message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Trace(StringView(message), CallerPath, CallerName, CallerLine);
	[Inline] public static void Info(String message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Info(StringView(message), CallerPath, CallerName, CallerLine);
	[Inline] public static void Success(String message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Success(StringView(message), CallerPath, CallerName, CallerLine);
	[Inline] public static void Warning(String message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Warning(StringView(message), CallerPath, CallerName, CallerLine);
	[Inline] public static void Error(String message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Error(StringView(message), CallerPath, CallerName, CallerLine);

	[Inline] public static void Trace<T>(T value, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Trace, value, CallerPath, CallerName, CallerLine);
	[Inline] public static void Info<T>(T value, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Info, value, CallerPath, CallerName, CallerLine);
	[Inline] public static void Success<T>(T value, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Success, value, CallerPath, CallerName, CallerLine);
	[Inline] public static void Warning<T>(T value, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Warning, value, CallerPath, CallerName, CallerLine);
	[Inline] public static void Error<T>(T value, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
		=> Print(.Error, value, CallerPath, CallerName, CallerLine);

	[NoReturn]
	public static void Fatal(StringView message,  String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
	{
		let msg = scope $"{message}\n{CallerName} ({CallerPath}:{CallerLine})";
		Print(.Fatal, msg, CallerPath, CallerName, CallerLine);
		Internal.FatalError(msg, 1);
	}

	private static void Print<T>(ELogLevel level, T val, String CallerPath, String CallerName, int CallerLine)
	{
		Print(level, StringView(scope $"{val}"), CallerPath, CallerName, CallerLine);
	}

	public static void Print(ELogLevel level, StringView message, String CallerPath = Compiler.CallerFilePath, String CallerName = Compiler.CallerMemberName, int CallerLine = Compiler.CallerLineNum)
	{
		if (level < LogLevel)
			return;

		let time =  DateTime.Now;

		let formattedtime = scope $"[{time.Hour:00}:{time.Minute:00}:{time.Second:00}:{time.Millisecond:000}]";
		let levelPrefix = level.Prefix;

		// If this is ever changed also change the prefix calculation formula to get only the message without any additional garbage (time, level...)
		String line = scope $"{formattedtime}{levelPrefix}: {message}";
#if DEBUG
		if(level >= LogCallerPathMinLevel)
		{
			line.AppendF($"\n\t{CallerPath}:{CallerLine}");
			if (!String.IsNullOrEmpty(CallerName))
				line.AppendF($"({CallerName})");
		}
#endif
#if BF_TEST_BUILD
		Console.WriteLine(line);
		return;
#endif

		let start = formattedtime.Length + levelPrefix.Length + 2; // + 2 because of the chars in prefix ": "
		if (_callbacks.HasListeners)
			_callbacks(level, time, line.Substring(start), line);
	}

	public static void Init(bool console, bool debugger)
	{
		if (console)
		{
			AddCallback(new (level, time, message, preferredFormat) => {
				let color = Console.ForegroundColor;
				Console.ForegroundColor = level.ConsoleColor;
				Console.WriteLine(preferredFormat);
				Console.ForegroundColor = color;
			});
		}

		if (debugger)
		{
			AddCallback(new (level, time, message, preferredFormat) => {
				System.Diagnostics.Debug.Write(level.ColorCodeStr);
				System.Diagnostics.Debug.Write(preferredFormat);
				System.Diagnostics.Debug.Write("\x02\n");
			});
		}
	}
}