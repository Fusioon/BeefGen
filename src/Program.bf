using System;
using System.IO;
using System.Collections;
using libclang_beef;

namespace BeefGen;

class Entry3
{
	struct TokenInfo : this(CXToken* tokens, uint32 tokenCount);

	enum TypedefKind
	{
		case OpaquePointer(StringView name);
		case FunctionPointer(StringView name);
		case NoDeclFound;
	}

	static String _src = new .() ~ delete _;
	static HashSet<String> _lookup = new .() ~ delete _;
 	static BumpAllocator _strAlloc = new .() ~ delete _;

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

		/*let path = scope $"{dir}/include/SODIUM_include/sodium.h";

		char8*[?] argv = .(scope $"-I{dir}/include/SODIUM_include");

		let index = clang_createIndex(0, 0);
		let unit = clang_createTranslationUnitFromSourceFile(index, path, 1, &argv[0], 0, null);
		let cursor = clang_getTranslationUnitCursor(unit);

		clang_visitChildren(cursor, (cursor, parent, userData) => {
			FilterTypes!(cursor, "include/SODIUM_include");
			
			switch (cursor.kind) {
				case .CXCursor_TypedefDecl when _lookup.Add(new:_strAlloc String(CursorSpelling!(cursor))): return TypedefDecl(cursor);
				case .CXCursor_FunctionDecl when _lookup.Add(new:_strAlloc String(CursorSpelling!(cursor))): return FuncDecl(cursor);
				case .CXCursor_StructDecl when _lookup.Add(new:_strAlloc String(CursorSpelling!(cursor))):  return StructDecl(clang_getCursorDefinition(cursor));
				case .CXCursor_EnumDecl when _lookup.Add(new:_strAlloc String(CursorSpelling!(cursor))): return EnumDecl(cursor);
				default:
			}

			return .CXChildVisit_Recurse;
		}, null);

		//Console.WriteLine(_src);
		//File.WriteAllText(scope $"{dir}/src/Box2DBeef.bf", scope $"namespace Box2DBeef;\nusing System;\n\nstatic\n{{\n{_src}}}");
		File.WriteAllText(scope $"{dir}/src/Sodium.bf", scope $"namespace libsodium.raw;\nusing System;\n\nstatic\n{{\n{_src}}}");
		//File.WriteAllText(scope $"{dir}/src/LibclangTest.bf", scope $"namespace LibclangTest;\nusing System;\n\nstatic\n{{\n{_src}}}");
		Console.Read();*/
	}

	static CXChildVisitResult EnumDecl(CXCursor cursor)
	{
		
		let tu = clang_Cursor_getTranslationUnit(cursor);
		let range = clang_getCursorReferenceNameRange(cursor, .CXNameRange_WantSinglePiece, 0);

		CXToken* tokens = ?;
		uint32 tokenCount = 0;

		clang_tokenize(tu, range, &tokens, &tokenCount);

		let enumName = CursorDisplayName!(cursor);
		bool unnamed = enumName.Contains("unnamed");

		let src = scope String();

		if (!unnamed)
			src.Append(scope $"[CRepr, AllowDuplicates]\npublic enum {CursorDisplayName!(cursor)} : int32\n{{\n");

		int members = 0;
		OuterScope:
		{
			for (uint32 i < tokenCount) {
				let tokenKind = clang_getTokenKind(tokens[i]);
				if (tokenKind != .CXToken_Identifier)
					continue;

				let loc = clang_getTokenLocation(tu, tokens[i]);
				let tCursor = clang_getCursor(tu, loc);

				if (tCursor.kind == .CXCursor_EnumConstantDecl) {
					let val = clang_getEnumConstantDeclValue(tCursor);

					if (!unnamed)
						src.Append(scope $"    {CursorDisplayName!(tCursor)} = {val},\n");
					else
						src.Append(scope $"    public const int32 {CursorDisplayName!(tCursor)} = {val};\n");

					members++;
				}
			}
		}

		if (!unnamed && members > 0) {
			src.RemoveFromEnd(2);
			src.Append(scope $"\n}}\n\n");
			_src.Append(src);
		}

		clang_disposeTokens(tu, tokens, tokenCount);
		return .CXChildVisit_Continue;
	}

	static CXChildVisitResult StructDecl(CXCursor cursor)
	{
		let tokenInfo = GetTokens!(cursor);
		if(DisambiguateTypedefKind(cursor, tokenInfo) case .OpaquePointer || clang_isCursorDefinition(cursor) == 0)
			return .CXChildVisit_Continue;
		
		OuterScope:
		{
			String fields = scope .();
			HashSet<String> lookup = scope .();

			let unit = clang_Cursor_getTranslationUnit(cursor);
			for (var i < tokenInfo.tokenCount) {
				let loc = clang_getTokenLocation(unit, tokenInfo.tokens[i]);
				let tokenCursor = clang_getCursor(unit, loc);
				let tokenKind = clang_getTokenKind(tokenInfo.tokens[i]);

				if (tokenKind != .CXToken_Keyword && tokenCursor.kind == .CXCursor_FieldDecl) {

					let type = clang_getCursorType(tokenCursor);
					GetDeepPointee(type, let indirections, let realType);

					if (realType.kind == .CXType_FunctionProto) {
						List<CXToken> parameterTokens = scope .();
						int32 offset = 0;

						var tokStr = scope String(StringifyToken!(tokenCursor, tokenInfo.tokens[i + offset]));
						while (tokStr != ";") {
							parameterTokens.Add(tokenInfo.tokens[i]);
							tokStr.Clear();
							tokStr.Append(StringifyToken!(tokenCursor, tokenInfo.tokens[i + offset]));
							offset++;
						}

						parameterTokens.Add(tokenInfo.tokens[i]);

						let p = FuncPtrParams(tokenInfo.tokens[i], unit, .. scope .());
						let rType = clang_getResultType(realType);
						
						
						let split = p.Split!('\n');

						uint32 index = (.)(split.Count - 1);
						CXType t = ?;

						Console.WriteLine(CursorDisplayName!(cursor));
						let param = scope String();

						while ((t = clang_getArgType(realType, index)).kind != .CXType_Invalid) {
							GetDeepPointee(t, let indirections2, let pRealType);

							param.Append(scope $"{TranslateType!(pRealType)}{PointerNotation!(indirections2)} {split[index]}, ");
							index++;
						}

						if (index > 0 && param.Length > 1)
							param.RemoveFromEnd(2);

						GetDeepPointee(rType, let indirections2, let rRealType);
						let str = scope:OuterScope $"    public function {TranslateType!(rType)}{PointerNotation!(indirections2)}({param}) {CursorSpelling!(tokenCursor)};\n";

						if (lookup.Add(scope:OuterScope String(CursorSpelling!(tokenCursor))))
							fields.Append(str);
					} else {

						int32 ofs = 0;
						if (clang_getCanonicalType(realType).kind == .CXType_FunctionProto) 
							ofs--;
						
						let str = scope:OuterScope $"    public {TranslateType!(realType)}{PointerNotation!(indirections + ofs)} {CursorSpelling!(tokenCursor)};\n";
						if (lookup.Add(scope:OuterScope String(CursorSpelling!(tokenCursor))))
							fields.Append(str);
					}
				}
			}

			_src.Append(scope $"[CRepr]\npublic struct {CursorSpelling!(cursor)}\n{{\n{fields}}}\n\n");
		}
		
		return .CXChildVisit_Continue;
	}

	static void FuncPtrParams(CXToken token, CXTranslationUnit unit, String outParameters)
	{
		let loc = clang_getTokenLocation(unit, token);
		var tokenCursor = clang_getCursor(unit, loc);

		let range = clang_getCursorExtent(tokenCursor);

		CXToken* realTokens = ?;
		uint32 numTokens = 0;
		clang_tokenize(unit, range, &realTokens, &numTokens);

		let str = scope String();
		for (uint32 i < numTokens) {

			let kind = clang_getTokenKind(realTokens[i]);
			let tokenStr = StringifyToken!(tokenCursor, realTokens[i]);

			if (tokenCursor.kind == .CXCursor_FieldDecl && kind == .CXToken_Punctuation && (tokenStr == "," || tokenStr == ")")) {
				str.Append(scope $"{StringifyToken!(tokenCursor, realTokens[i - 1])}\n");
			}
		}


		outParameters.Append(str);
	}

	static CXChildVisitResult FuncDecl(CXCursor cursor)
	{
		if (clang_Cursor_isFunctionInlined(cursor) != 0)
			return .CXChildVisit_Continue;

		let numArgTypes = clang_Cursor_getNumArguments(cursor);
		List<String> paramTypes = scope .();

		for (let i < numArgTypes) {
			paramTypes.Add(scope:: String());
			let argCursor = clang_Cursor_getArgument(cursor, (.)i);
			var argType = clang_getCursorType(argCursor);

			var pointee = clang_getPointeeType(argType);
			if ((argType.kind == .CXType_Pointer && pointee.kind == .CXType_Elaborated) || argType.kind == .CXType_Elaborated ) {

				let typedefCursor = clang_getTypeDeclaration(pointee.kind == .CXType_Invalid ? argType : pointee);
				let result = DisambiguateTypedefKind(typedefCursor, GetTokens!(typedefCursor));

				if (result case .OpaquePointer(let name)) {
					paramTypes[i].Append(scope $"{name} {CursorSpelling!(argCursor)}");
					continue;
				}
			}

			GetDeepPointee(argType, var indirections, let realType);

			let canonical = clang_getCanonicalType(realType);
			if (canonical.kind == .CXType_FunctionProto && indirections > 0) {
				indirections--;
			}

			paramTypes[i].Append(scope $"{TranslateType!(realType)}{PointerNotation!(indirections)} {CursorDisplayName!(argCursor)}");
		}

		let retType = clang_getResultType(clang_getCursorType(cursor));
		GetDeepPointee(retType, var indirections, let realType);
		//let canonicalRet = clang_getCanonicalType(realType);

		let parameters = scope String();

		for (let i < paramTypes.Count) {
			parameters.Append(scope $"{paramTypes[i]}, ");
			if (i == paramTypes.Count - 1)
				parameters.RemoveFromEnd(2);
		}

		_src.Append(scope $"[CLink]\npublic static extern {TranslateType!(realType)}{PointerNotation!(indirections)} {CursorSpelling!(cursor)}({parameters});\n\n");
		return .CXChildVisit_Continue;
	}

	static void GetDeepPointee(CXType pointee, out int32 indirections, out CXType realType)
	{
		var pointee;
		indirections = 0;

		while(pointee.kind == .CXType_Pointer) {
			pointee = clang_getPointeeType(pointee);
			indirections++;
		}

		realType = pointee;
	}

	static mixin PointerNotation(int32 count)
	{
		let str = scope:mixin String();
		for (let i < count)
			str.Append("*");

		str
	}

	static mixin CursorDisplayName(CXCursor cursor)
	{
		let displayName = clang_getCursorDisplayName(cursor);
		let str = StringView(clang_getCString(displayName));
		defer:mixin clang_disposeString(displayName);

		str
	}

	static mixin CursorSpelling(CXCursor cursor)
	{
		let displayName = clang_getCursorSpelling(cursor);
		let str = StringView(clang_getCString(displayName));
		defer:mixin clang_disposeString(displayName);

		str
	}

	static mixin TranslateType(CXType t)
	{
		let canonical = clang_getCanonicalType(t);
		let str = scope:mixin String();
		switch (canonical.kind) {
			case .CXType_Int: str.Append("int32");
			case .CXType_UShort: str.Append("uint16");
			case .CXType_Short: str.Append("int16");
			case .CXType_ULongLong: str.Append("uint64");
			case .CXType_LongLong: str.Append("int64");
			case .CXType_Float: str.Append("float");
			case .CXType_Double: str.Append("double");
			case .CXType_UInt: str.Append("uint32");
			case .CXType_Bool: str.Append("bool");
			case .CXType_Void: str.Append("void");
			case .CXType_Char_S: fallthrough;
			case .CXType_SChar:	str.Append("char8");
			case .CXType_UChar: fallthrough;
			case .CXType_Char_U: str.Append("uint8");
			case .CXType_Record: fallthrough;
			case .CXType_ConstantArray: str..Append(TypeSpelling!(t))..Replace("char", "uint8")..Replace("unsigned ", "");
			case .CXType_Invalid: str.Append("INVALID_TYPE");
			case .CXType_FunctionProto: { str..Append(TypeSpelling!(t))..Replace("*", ""); }
			case .CXType_Enum: str.Append(TypeSpelling!(t));

			default:
		}
		str..Replace("struct ", "")
		   ..Replace("const ", "")
		   ..Replace("_t", "")
		   ..Replace(" *", "* ");

		str
	}

	static CXChildVisitResult TypedefDecl(CXCursor cursor)
	{
		let result = DisambiguateTypedefKind(cursor, GetTokens!(cursor));
		if (result case .OpaquePointer(let name)) {}
			//Console.WriteLine(scope $"public struct {name} : int32 {{}}\n");

		if (result case .FunctionPointer(let name)) {
			//GetDeepPointee(clang_getCursorType(cursor), ?, let canonicalType);

			let underlying = clang_getTypedefDeclUnderlyingType(cursor);
			let tokenInfo = GetTokens!(cursor);
			let tu = clang_Cursor_getTranslationUnit(cursor);

			List<String> parameterNames = scope .();

			for (let i < tokenInfo.tokenCount) {
				let tokenKind = clang_getTokenKind(tokenInfo.tokens[i]);
				let tl = clang_getTokenLocation(tu, tokenInfo.tokens[i]);
				let tokenCursor = clang_getCursor(tu, tl);

				if (tokenCursor.kind != .CXCursor_ParamDecl)
					continue;

				if (tokenKind == .CXToken_Punctuation || tokenKind == .CXToken_Keyword)
					continue;

				parameterNames.Add(scope:: String(StringifyToken!(cursor, tokenInfo.tokens[i]))..Replace("*", ""));
			}

			let retType = clang_getResultType(clang_getCursorType(cursor));
			GetDeepPointee(retType, let indirections, let realRetType);

			uint32 arg = 0;
			//Console.Write(scope $"{CursorSpelling!(cursor)}(");
			let funcPtr = scope $"public function {TranslateType!(realRetType)}{PointerNotation!(indirections)} {name}(";
			for (let p in parameterNames) {
				let argType = clang_getArgType(underlying, arg);
				GetDeepPointee(argType, let indir, let realParamType);

				funcPtr.Append(scope $"{TranslateType!(realParamType)}{PointerNotation!(indir)} {p}, ");
				arg++;
			}
			

			if (arg > 0)
				funcPtr.RemoveFromEnd(2);

			funcPtr.Append(");\n\n");
			_src.Append(funcPtr);
		}
			

		return .CXChildVisit_Continue;
	}

	static TypedefKind DisambiguateTypedefKind(CXCursor cursor, TokenInfo tokenInfo)
	{
		let type = clang_getTypedefDeclUnderlyingType(cursor);

		//Console.WriteLine(scope $"Type kind: { type.kind } : Name { TypeSpelling!(type) }")

		switch (tokenInfo.tokenCount) {
			//Opaque pointers/handles
			case 4 when CompareToken(cursor, tokenInfo.tokens[1], "struct"): fallthrough;
			case 5 when CompareToken(cursor, tokenInfo.tokens[1], "struct"): {

				int nextToken = CompareToken(cursor, tokenInfo.tokens[3], "*") ? 4 : 3;
				if (CompareTokens(cursor, tokenInfo.tokens[2], tokenInfo.tokens[nextToken])) {
					return .OpaquePointer(new:_strAlloc String(StringifyToken!(cursor, tokenInfo.tokens[2])));
				}
			}
			//FuncPtr
			//case when (tokenInfo.tokenCount > 4 && CompareToken(cursor, tokenInfo.tokens[3], "*") && CompareToken(cursor, tokenInfo.tokens[2], "(")): Console.WriteLine("Possibly func ptr");
			//case when (tokenInfo.tokenCount > 3 && clang_getTypedefDeclUnderlyingType(cursor).kind == .CXType_FunctionProto): Console.WriteLine("Possibly func ptr");

		}

		GetDeepPointee(type, let indirections, let realType);
			
		if (realType.kind == .CXType_FunctionProto) {
			//this corrupts the stack ofc, should probably fix
			return .FunctionPointer(new:_strAlloc String(CursorSpelling!(cursor)));
		}

		return .NoDeclFound;
	}

	static bool CompareTokens(CXCursor c, CXToken t1, CXToken t2)
	{
		return CompareToken(c, t1, StringifyToken!(c, t2));
	}

	static bool CompareToken(CXCursor c, CXToken t, StringView comp)
	{
		let str = StringifyToken!(c, t);
		return str.Equals(comp);
	}

	static mixin TypeSpelling(CXType type)
	{
		let spelling = clang_getTypeSpelling(type);
		let str = StringView(clang_getCString(spelling));

		defer:mixin clang_disposeString(spelling);

		str
	}

	static mixin GetTokens(CXCursor c)
	{
		let range = clang_getCursorReferenceNameRange(c, .CXNameRange_WantSinglePiece, 0);
		let unit = clang_Cursor_getTranslationUnit(c);

		CXToken* tokens = ?;
		uint32 tokenCount = 0;

		clang_tokenize(unit, range, &tokens, &tokenCount);
		defer:mixin clang_disposeTokens(unit, tokens, tokenCount);

		let tokenInfo = TokenInfo(tokens, tokenCount);
		tokenInfo
	}

	static mixin FilterTypes(CXCursor current, StringView filterBy)
	{
		CXFile file = ?;
		uint32 line = ?, column = ?, offset = ?; 

		clang_getExpansionLocation(clang_getCursorLocation(current), &file, &line, &column, &offset);

		let tmpStr = clang_getFileName(file);
		defer:mixin clang_disposeString(tmpStr);

		let fileName = StringView(clang_getCString(tmpStr));
		let canonicalPath = Path.GetAbsolutePath(null, fileName, .. scope .())..Replace('\\', '/');

		if (!canonicalPath.Contains(filterBy)) {
			return CXChildVisitResult.CXChildVisit_Continue;
		}

		if (canonicalPath.Contains("SDL_iostream")) {
			return CXChildVisitResult.CXChildVisit_Continue;
		}
	}

	static mixin StringifyToken(CXCursor c, CXToken token)
	{
		let spelling = clang_getTokenSpelling(clang_Cursor_getTranslationUnit(c), token);
		let str = StringView(clang_getCString(spelling));
		defer:mixin clang_disposeString(spelling);

		str
	}
}