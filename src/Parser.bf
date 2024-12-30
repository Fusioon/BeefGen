using System;
using System.Interop;
using System.Collections;

using libclang_beef;
using System.IO;
using System.Diagnostics;

using internal BeefGen;

namespace BeefGen;

enum EStorageKind
{
	case Unknown,
	Extern;

	public static operator Self(CX_StorageClass other)
	{
		if (other == .CX_SC_Extern)
			return .Extern;

		return .Unknown;
	}
}

enum ELinkageKind
{
	case Unknown, External, Internal, UniqueExternal, None;

	public static operator Self(CXLinkageKind kind)
	{
		switch (kind)
		{
		case .CXLinkage_External: return .External;
		case .CXLinkage_Internal: return .Internal;
		case .CXLinkage_UniqueExternal: return .UniqueExternal;
		case .CXLinkage_NoLinkage: return .None;
		default:
		}

		return .Unknown;
	}
}

class Parser : IRawAllocator
#if BF_ENABLE_REALTIME_LEAK_CHECK
	, ITypedAllocator
#endif
{

#region TYPES	
	public class TypeDef
	{
		public append String name;
		public bool unnamed;
		public TypeRef baseType;

		public void SetUnnamed() => unnamed = name.Contains("unnamed");
	}

	public class EnumDef : TypeDef
	{
		public class NameValuePair
		{
			public append String name;
			public append String value;
		}	

		public append List<NameValuePair> values;
	}

	public class TypeRef
	{
		public append String raw;

		public append String typeString;
		//public TypeRef next;
		public bool isConst;
		public bool isRef;
		public int ptrDepth;

		public List<int64> sizedArray;

		public TypeDef typeDef;
	}

	public class VariableDecl
	{
		public append String name;
		public append TypeRef type;
	}

	public class GlobalVariableDecl : VariableDecl
	{
		public EStorageKind storageKind;
	}

	public class StructTypeDef : TypeDef
	{
		public enum ETag
		{
			case Unknown,
				Struct,
				Class,
				Union;
		}


		public ETag tag;
		public append List<VariableDecl> fields;

		public List<TypeDef> innerTypes;
		public bool isCompleteDef;
	}

	public class FunctionTypeDef : TypeDef
	{
		public bool typeOnly;
		public append TypeRef functionType;

		public append TypeRef resultType;
		public append List<VariableDecl> args;
		public bool isVarArg;

		public ELinkageKind linkageType;
		public CallingConventionAttribute.Kind callConv = .Unspecified;
		public List<String> attributes;
	}

	public enum ETypeAliasFlags
	{
		None = 0x00,
		Primitive = 0x01,
		Struct = 0x02,
		Enum = 0x04,
		Function = 0x08,

		Anonymous = 0x20,
		ForceGenerate = 0x40,
		Resolved = 0x80,
	}

	public class TypeAliasDef : TypeDef
	{
		public append TypeRef alias;

		public ETypeAliasFlags flags;
	}

	public class MacroDef : TypeDef
	{
		public List<String> args;
		public append String value;
	}

	protected struct IgnoreWritesRestore : this(SelfOuter inst, bool prev), IDisposable
	{
		public void Dispose()
		{
			inst.RestoreWrites(this);
		}
	}

#endregion

	append BumpAllocator _alloc;

	public append Dictionary<String, TypeDef> types;
	public append List<EnumDef> enums;
	public append List<StructTypeDef> structs;
	public append List<FunctionTypeDef> functions;
	public append Dictionary<String, TypeAliasDef> aliasMap;
	public append List<GlobalVariableDecl> globalVars;
	public append Dictionary<String, MacroDef> macros;

	Settings _settings;
	bool _ignoreWrites = false;

	public void* Alloc(int size, int align) => _alloc.Alloc(size, align);

	public void Free(void* ptr) => _alloc.Free(ptr);

	public void* AllocTyped(Type type, int size, int align)
	{
#if BF_ENABLE_REALTIME_LEAK_CHECK
		return _alloc.AllocTyped(type, size, align);
#else
		return Alloc(size, align);
#endif
	}

	void AddType(EnumDef def)
	{
		Debug.Assert(def.name.Length > 0);

		if (_ignoreWrites)
			return;

		types.Add(def.name, def);
		enums.Add(def);
	}

	void AddType(StructTypeDef def)
	{
		Debug.Assert(def.name.Length > 0);

		if (_ignoreWrites)
			return;

		types.Add(def.name, def);
		structs.Add(def);
	}

	void AddType(FunctionTypeDef def)
	{
		Debug.Assert(def.name.Length > 0);

		if (_ignoreWrites)
			return;

		types.Add(def.name, def);
		functions.Add(def);
	}

	void AddType(TypeAliasDef def)
	{
		Debug.Assert(def.name.Length > 0);

		if (_ignoreWrites)
			return;

		if (types.TryAdd(def.name, def))
		{
			aliasMap.TryAdd(def.name, def);
		}
	}

	protected IgnoreWritesRestore IgnoreWrites()
	{
		let prev = _ignoreWrites;
		_ignoreWrites = true;
		return .(this, prev);
	}

	protected void RestoreWrites(IgnoreWritesRestore v) => _ignoreWrites = v.prev;

	void PrintDiagnostics(CXTranslationUnit tu, out bool hadFatalError)
	{
		hadFatalError = false;
	    let numDiagnostics = clang_getNumDiagnostics(tu);
	  	for (let i < numDiagnostics)
		{
			CXDiagnostic diag = clang_getDiagnostic(tu, i);

			ELogLevel level;
			switch (clang_getDiagnosticSeverity(diag))
			{
			case .CXDiagnostic_Note, .CXDiagnostic_Ignored: continue;
			case .CXDiagnostic_Fatal:
			{
				level = .Fatal;
				hadFatalError = true;
			}
			case .CXDiagnostic_Error: level = .Error;
			case .CXDiagnostic_Warning: level = .Warning;
			}

		    CXString diagSpelling = clang_getDiagnosticSpelling(diag);
			StringView message = .(clang_getCString(diagSpelling));
			let loc = clang_getDiagnosticLocation(diag);

			CXFile file = default;
			uint32 line = 0, col = 0, offset = 0;
			clang_getSpellingLocation(loc, &file, &line, &col, &offset);

			CXString fileName = clang_getFileName(file);
			String filePath = scope .();
			filePath.Append(clang_getCString(fileName));
			clang_disposeString(fileName);

			Log.Print(level, message, filePath, "", line);

		    clang_disposeString(diagSpelling);
			clang_disposeDiagnostic(diag);
		}
		
	}

	public Result<void> Parse(Settings settings)
	{
		_settings = settings;

		List<char8*> argv = scope .(_settings._includeDirs.Count + _settings._commandLineArgs.Count);
		
		for (let includeDir in _settings._includeDirs)
		{
			argv.Add(new:this $"-I{includeDir}");
		}

		for (let arg in _settings._commandLineArgs)
			argv.Add(arg);

		bool hadFatalErr = false;
		for (let inputFile in _settings._inputFiles)
		{
			let index = clang_createIndex(0, 0);
			let unit = clang_parseTranslationUnit(index, inputFile, argv.Ptr, (.)argv.Count, null, 0, .CXTranslationUnit_DetailedPreprocessingRecord);
			
			//let unit = clang_createTranslationUnitFromSourceFile(index, inputFile, (.)argv.Count, argv.Ptr, 0, null);
			let cursor = clang_getTranslationUnitCursor(unit);

			PrintDiagnostics(unit, let fatalErr);
			hadFatalErr |= fatalErr;

			(Self _this, StringView input) ctx = (this, inputFile);

			clang_visitChildren(cursor, (cursor, parent, userData) => {
				(Self _this, StringView input) = *(.)userData;
				return _this.ForEachChildren(input, cursor, parent);
			}, &ctx);

			clang_disposeTranslationUnit(unit);
			clang_disposeIndex(index);
		}	

		return hadFatalErr ? .Err : .Ok;
	}

	CXChildVisitResult ForEachChildren(StringView inputFile, CXCursor cursor, CXCursor parent)
	{
		EDeclKind kind;
		switch (cursor.kind)
		{
			case .CXCursor_TypedefDecl: kind = .Typedef;
			case .CXCursor_FunctionDecl: kind = .Function;
			case .CXCursor_StructDecl: kind = .Struct;
			case .CXCursor_UnionDecl: kind = .Struct;
			case .CXCursor_EnumDecl: kind = .Enum;
			case .CXCursor_VarDecl: kind = .Variable;
			case .CXCursor_MacroDefinition: kind = .Macro;

			default: return .CXChildVisit_Recurse;
		}

		let name = CursorSpelling(cursor, .. scope .());
		if (_settings.typeFilter != null)
		{
			CXFile file = ?;
			uint32 line = ?, column = ?, offset = ?; 

			clang_getExpansionLocation(clang_getCursorLocation(cursor), &file, &line, &column, &offset);

			let tmpStr = clang_getFileName(file);
			clang_disposeString(tmpStr);

			let fileName = StringView(clang_getCString(tmpStr));
			let canonicalPath = Path.GetAbsolutePath(null, fileName, .. scope .())..Replace('\\', '/');

			if (_settings.typeFilter(name, kind, .(inputFile, canonicalPath, line, column, offset)) == false)
			{
				return CXChildVisitResult.CXChildVisit_Continue;
			}
		}

		switch (kind)
		{
			case .Typedef: return TypedefDecl(cursor, ?);
			case .Function: return FuncDecl(cursor, ?);
			case .Struct:  return StructDecl(cursor, ?);
			case .Enum: return EnumDecl(cursor, ?);
			case .Variable: return VarDecl(cursor);
			case .Macro: return MacroDecl(cursor);
		}
	}

	CXChildVisitResult MacroDecl(CXCursor cursor)
	{
		if (clang_Cursor_isMacroBuiltin(cursor) != 0)
			return .CXChildVisit_Continue;

		let macroName = CursorSpelling(cursor, .. scope .());

		let range = clang_getCursorExtent(cursor);
		let unit = clang_Cursor_getTranslationUnit(cursor);
		CXToken *tokens = ?;
		uint32 tokenCount = 0;
		clang_tokenize(unit, range, &tokens, &tokenCount);

		String buffer = scope .();
		TypeAliasDef x;
		let fnLike = clang_Cursor_isMacroFunctionLike(cursor) != 0;
		uint32 index = 1;
		if (fnLike)
		{
			Runtime.Assert(clang_getTokenKind(tokens[index++]) == .CXToken_Punctuation);

			// Parse args
		}

		for (uint32 i = 1; i < tokenCount; ++i)
		{
			let k = clang_getTokenKind(tokens[i]);
			CXString tokenSpelling = clang_getTokenSpelling(unit, tokens[i]);
			buffer.Append(clang_getCString(tokenSpelling));
			clang_disposeString(tokenSpelling);
		}

		clang_disposeTokens(unit, tokens, tokenCount);
		if (tokenCount > 1)
			Log.Info(scope $"{macroName} {buffer}");
		return .CXChildVisit_Continue;
	}

	CXChildVisitResult TypedefDecl(CXCursor cursor, out TypeAliasDef typealiasDef)
	{
		typealiasDef = new:this TypeAliasDef();
		CursorSpelling(cursor, typealiasDef.name);
		AddType(typealiasDef);

		let resolvedType = clang_getTypedefDeclUnderlyingType(cursor);
		(?, let flags) = GetTypeRef(resolvedType, typealiasDef.alias, false, ?, cursor);
		typealiasDef.flags = flags;

		return .CXChildVisit_Continue;
	}

	CXChildVisitResult FuncDecl(CXCursor cursor, out FunctionTypeDef functionDef)
	{
		if (clang_Cursor_isFunctionInlined(cursor) != 0)
		{
			functionDef = null;
			return .CXChildVisit_Continue;
		}

		let link = clang_getCursorLinkage(cursor);

		functionDef = new:this FunctionTypeDef();
		CursorSpelling(cursor, functionDef.name);
		functionDef.SetUnnamed();
		AddType(functionDef);
		functionDef.linkageType = link;

		if (functionDef.name == "SDL_vsscanf")
			NOP!();

		let functionType = clang_getCursorType(cursor);
		let callconv = clang_getFunctionTypeCallingConv(functionType);
		switch (callconv)
		{
		case .CXCallingConv_C: functionDef.callConv = .Cdecl;
		case .CXCallingConv_X86FastCall: functionDef.callConv = .Fastcall;
		case .CXCallingConv_X86StdCall: functionDef.callConv = .Stdcall;
		default: Runtime.FatalError();
		}
		
		functionDef.isVarArg = (clang_isFunctionTypeVariadic(functionType) != 0);
		functionDef.typeOnly = false;

		let returnType = clang_getResultType(functionType);
		GetTypeRef(returnType, functionDef.resultType, false, ?, cursor);

		let numArgs = clang_getNumArgTypes(functionType);
		
		List<String> argNames = scope .();
		(Self _this, FunctionTypeDef def, List<String> argNames) ctx = (this, functionDef, argNames);

		clang_visitChildren(cursor, (cursor, parent, client_data) => {
			(Self _this, FunctionTypeDef def, List<String> argNames) = *(.)client_data;

			let kind = clang_getCursorKind(cursor);
			switch(kind)
			{
			case .CXCursor_ParamDecl:
				{
					let name = CursorSpelling(cursor, .. new:_this String());
					argNames.Add(name);
				}
			default:
			}
			return .CXChildVisit_Continue;
		}, &ctx);
		Runtime.Assert(numArgs == argNames.Count);

		for (let i < numArgs)
		{
			let argType = clang_getArgType(functionType, (.)i);
			let arg = new:this VariableDecl();
			arg.name.Set(argNames[i]);
			GetTypeRef(argType, arg.type, false, ?, cursor);
			functionDef.args.Add(arg);
		}


		return .CXChildVisit_Continue;
	}

	bool MatchLocation(StringView lhs, StringView rhs)
	{
		int GetFilenameStart(StringView path)
		{
			int length = path.Length;
			for (int i = length; --i >= 0; )
			{
				char8 ch = path[i];
				if (ch == Path.DirectorySeparatorChar || ch == Path.AltDirectorySeparatorChar || ch == Path.VolumeSeparatorChar)
				{
					return i;
				}
			}
			return -1;
		}

		let lhsStart = GetFilenameStart(lhs);
		let rhsStart = GetFilenameStart(rhs);
		if (lhsStart == -1 || rhsStart == -1)
			return false;

		return lhs.Substring(lhsStart) == rhs.Substring(rhsStart);
	}

	CXChildVisitResult ForEachStructField(CXCursor fieldCursor, CXCursor parent, StructTypeDef typedef)
	{
		let kind = clang_getCursorKind(fieldCursor);
		switch (kind)
		{
		case .CXCursor_FieldDecl:
			{
				CXType fieldType = clang_getCursorType(fieldCursor);

				let fieldDecl = new:this VariableDecl();
				CursorSpelling(fieldCursor, fieldDecl.name);
				(?, let flags) = GetTypeRef(fieldType, fieldDecl.type, false, ?, fieldCursor);
				if (flags.HasFlag(.Anonymous))
				{
					Runtime.Assert(typedef.innerTypes != null && typedef.innerTypes.Count > 0);
					let top = typedef.innerTypes.Back;
					Runtime.Assert(MatchLocation(fieldDecl.type.typeString, top.name));
					
					top.name..Set(fieldDecl.name)..ToUpper().Append("_T");
					fieldDecl.type.typeString.Set(top.name);
				}

				typedef.fields.Add(fieldDecl);
			}

		case .CXCursor_StructDecl, .CXCursor_UnionDecl, .CXCursor_EnumDecl, .CXCursor_TypedefDecl:
			{
				using (IgnoreWrites())
				{
					TypeDef type;
					switch (_)
					{
					case .CXCursor_StructDecl, .CXCursor_UnionDecl:
						{
							StructDecl(fieldCursor, let structType);
							type = structType;
						}
					case .CXCursor_EnumDecl:
						{
							EnumDecl(fieldCursor, let enumType);
							type = enumType;
						}
					case .CXCursor_TypedefDecl:
						{
							TypedefDecl(fieldCursor, let typedefDef);
							type = typedefDef;
						}
					default: Runtime.FatalError();
					}
					typedef.innerTypes ??= new:this List<TypeDef>();
					typedef.innerTypes.Add(type);
				}	
			}
		default:
		}
		return .CXChildVisit_Continue;
	}

	CXChildVisitResult StructDecl(CXCursor cursor, out StructTypeDef typedef)
	{
		if (clang_isCursorDefinition(cursor) == 0)
		{
			typedef = null;
			return .CXChildVisit_Continue;
		}

		typedef = new:this StructTypeDef();
		CursorSpelling(cursor, typedef.name);
		typedef.SetUnnamed();

		AddType(typedef);

		CXType type = clang_getCursorType(cursor);
		CXCursor declCursor = clang_getTypeDeclaration(type);
		CXCursorKind kind = clang_getCursorKind(declCursor);
		switch (kind)
		{
		case .CXCursor_StructDecl: typedef.tag = .Struct;
		case .CXCursor_UnionDecl: typedef.tag = .Union;
		case .CXCursor_ClassDecl: typedef.tag = .Class;
		default: Runtime.FatalError();
		}
		
		(Self _this, StructTypeDef typedef) ctx = (this, typedef);

		clang_visitChildren(cursor, (cursor, parent, client_data) => {
			(Self _this, StructTypeDef typedef) = *(.)client_data;
			return _this.ForEachStructField(cursor, parent, typedef);
		}, &ctx);

		return .CXChildVisit_Continue;
	}

	CXChildVisitResult EnumDecl(CXCursor cursor, out EnumDef def)
	{
		let tu = clang_Cursor_getTranslationUnit(cursor);
		let range = clang_getCursorReferenceNameRange(cursor, .CXNameRange_WantSinglePiece, 0);

		CXToken* tokens = ?;
		uint32 tokenCount = 0;

		clang_tokenize(tu, range, &tokens, &tokenCount);

		def = new:this EnumDef();
		CursorDisplayName(cursor, def.name);
		def.SetUnnamed();
		AddType(def);

		let baseType = clang_getEnumDeclIntegerType(cursor);
		if (baseType.kind != .CXType_Int)
		{
			def.baseType = new .();
			GetTypeRef(baseType, def.baseType, false, ?);
		}

		for (uint32 i < tokenCount) {
			let tokenKind = clang_getTokenKind(tokens[i]);
			if (tokenKind != .CXToken_Identifier)
				continue;

			let loc = clang_getTokenLocation(tu, tokens[i]);
			let tCursor = clang_getCursor(tu, loc);

			if (tCursor.kind == .CXCursor_EnumConstantDecl) {
				let val = clang_getEnumConstantDeclValue(tCursor);

				let value = new:this EnumDef.NameValuePair();
				CursorDisplayName(tCursor, value.name);
				val.ToString(value.value);
				def.values.Add(value);
			}
		}

		clang_disposeTokens(tu, tokens, tokenCount);
		return .CXChildVisit_Continue;
	}

	CXChildVisitResult VarDecl(CXCursor cursor)
	{
		let storageClass = clang_Cursor_getStorageClass(cursor);

		let decl = new:this GlobalVariableDecl();
		CursorDisplayName(cursor, decl.name);
		decl.storageKind = storageClass;
		let type = clang_getCursorType(cursor);
		GetTypeRef(type, decl.type, false, ?, cursor);
		globalVars.Add(decl);

		return .CXChildVisit_Continue;
	}

	(CXType, ETypeAliasFlags) GetTypeRef(CXType type, TypeRef result, bool skipRaw, out int32 indirs, CXCursor cursor = default)
	{
		GetDeepPointee(type, out indirs, let realType);

		let canonicalType = clang_getCanonicalType(realType);
		if (!skipRaw)
		{
			TypeSpelling(canonicalType, result.raw);
			result.ptrDepth = indirs;
		}

		ETypeAliasFlags aliasFlags = .None;

		mixin SetPrimitive(String name)
		{
			result.typeString.Set(name);
			aliasFlags |= .Primitive;
		}

		switch (canonicalType.kind)
		{
			case .CXType_Int: SetPrimitive!(nameof(c_int));
			case .CXType_UShort: SetPrimitive!(nameof(c_ushort));
			case .CXType_Short: SetPrimitive!(nameof(c_short));
			case .CXType_ULong: SetPrimitive!(nameof(c_ulong));
			case .CXType_Long: SetPrimitive!(nameof(c_long));
			case .CXType_ULongLong: SetPrimitive!(nameof(c_ulonglong));
			case .CXType_LongLong: SetPrimitive!(nameof(c_longlong));
			case .CXType_Float: SetPrimitive!(nameof(float));
			case .CXType_Double: SetPrimitive!(nameof(double));
			case .CXType_UInt: SetPrimitive!(nameof(c_uint));
			case .CXType_Bool: SetPrimitive!(nameof(c_bool));
			case .CXType_Void: SetPrimitive!(nameof(void));
			case .CXType_Char_S, .CXType_SChar:	SetPrimitive!(nameof(c_char));
			case .CXType_UChar, .CXType_Char_U: SetPrimitive!(nameof(c_uchar));
			case .CXType_Record, .CXType_Enum:
			{
				var unqalType = clang_getUnqualifiedType(canonicalType);

				TypeSpelling(unqalType, result.typeString);
				if (result.typeString.Contains("unnamed"))
					aliasFlags |= .Anonymous;

				if (_ == .CXType_Enum)
				{
					aliasFlags |= .Enum;
					result.typeString.Replace("enum ", "");
				}
				else
				{
					aliasFlags |= .Struct;
					result.typeString..Replace("struct ", "")..Replace("union ", "");
				}
				
			}
			case .CXType_ConstantArray:
			{
				var t = canonicalType;
				result.sizedArray ??= new:this List<int64>();
				repeat
				{
					let size = clang_getArraySize(canonicalType);
					t = clang_getArrayElementType(canonicalType);
					result.sizedArray.Add(size);
				}
				while (t.kind == .CXType_ConstantArray);
				(?, let flags) = GetTypeRef(t, result, true, ?);
				aliasFlags |= flags;
			}
			case .CXType_IncompleteArray:
			{
				let elementType = clang_getArrayElementType(canonicalType);
				(?, let flags) = GetTypeRef(elementType, result, true, let depth);
				result.ptrDepth = depth + 1;
				aliasFlags |= flags;
			}
			case .CXType_FunctionProto:
			{
				aliasFlags |= .Function;

				let functionDef = new:this FunctionTypeDef();
				result.typeDef = functionDef;

				functionDef.isVarArg = (clang_isFunctionTypeVariadic(realType) != 0);
				functionDef.typeOnly = true;

				let returnType = clang_getResultType(realType);
				GetTypeRef(returnType, functionDef.resultType, false, ?, cursor);
				
				let numArgs = clang_getNumArgTypes(realType);

				List<String> argNames = scope .();

				if (numArgs > 0)
				{
					(Self _this, List<String> argNames) ctx = (this, argNames);
					clang_visitChildren(cursor, (cursor, parent, client_data) => {
						(Self _this, List<String> argNames) = *(.)client_data;
						if (cursor.kind == .CXCursor_ParamDecl)
						{
							let name = CursorSpelling(cursor, .. new:_this String());
							argNames.Add(name);
						}
						return .CXChildVisit_Continue;
					}, &ctx);
				}

				Runtime.Assert(numArgs == argNames.Count);

				for (let i < numArgs)
				{
					let argType = clang_getArgType(realType, (.)i);
					let arg = new:this VariableDecl();
					arg.name.Set(argNames[i]);
					GetTypeRef(argType, arg.type, false, ?, cursor);
					functionDef.args.Add(arg);
				}
			}

			case .CXType_Pointer:
			{
				if (realType.kind == .CXType_Elaborated)
				{
					TypeSpelling(realType, result.typeString);
					if (result.typeString == "va_list")
					{
						result.typeString.Set(nameof(VarArgs));
					}
				}
			}
			
			case .CXType_Invalid:
			{
				Runtime.FatalError();
			}

			default:
		}
		if (aliasMap.TryGetValue(result.typeString, let value))
		{
			value.flags |= .Resolved;
		}

		return (realType, aliasFlags);
	}

	static void CursorDisplayName(CXCursor cursor, String buffer)
	{
		let displayName = clang_getCursorDisplayName(cursor);
		let str = clang_getCString(displayName);
		buffer.Append(str);
		clang_disposeString(displayName);
	}

	static void CursorSpelling(CXCursor cursor, String buffer)
	{
		let displayName = clang_getCursorSpelling(cursor);
		let str = clang_getCString(displayName);
		buffer.Append(str);
		clang_disposeString(displayName);
	}

	static void TypeSpelling(CXType type, String buffer)
	{
		let displayName = clang_getTypeSpelling(type);
		let str = clang_getCString(displayName);
		buffer.Append(str);
		clang_disposeString(displayName);
	}

	static void StringifyToken(CXCursor c, CXToken token, String buffer)
	{
		let spelling = clang_getTokenSpelling(clang_Cursor_getTranslationUnit(c), token);
		let str = clang_getCString(spelling);
		buffer.Append(str);
		clang_disposeString(spelling);
	}

	static mixin GetTokens(CXCursor c)
	{
		let range = clang_getCursorReferenceNameRange(c, .CXNameRange_WantSinglePiece, 0);
		let unit = clang_Cursor_getTranslationUnit(c);

		CXToken* tokens = ?;
		uint32 tokenCount = 0;

		clang_tokenize(unit, range, &tokens, &tokenCount);
		defer:mixin clang_disposeTokens(unit, tokens, tokenCount);

		(tokens, tokenCount)
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

		String tokenStr = scope .(32);
		String tmp = scope .(64);
		for (uint32 i < numTokens)
		{
			let kind = clang_getTokenKind(realTokens[i]);
			StringifyToken(tokenCursor, realTokens[i], tokenStr..Clear());

			if (tokenCursor.kind == .CXCursor_FieldDecl && kind == .CXToken_Punctuation && (tokenStr == "," || tokenStr == ")"))
			{
				StringifyToken(tokenCursor, realTokens[i - 1], tmp..Clear());
				str.Append(tmp);
				str.Append('\n');
			}
		}


		outParameters.Append(str);
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
}