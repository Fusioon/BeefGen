#ifndef __TEST_H__
#pragma once

#define CONST_CHAR8 '8'
#define CONST_CHAR8_HEX '\x72'
#define CONST_CHAR_UTF8 u8'c'
#define CONST_CHAR_UTF16 u'\U00008C93'
#define CONST_CHAR_UTF32 U'\U0001f34c'
#define CONST_CHAR_WIDE L'č'

#define CONST_BOOL_FALSE false
#define CONST_BOOL_TRUE true

#define CONST_STRING_8 "What is this"
#define CONST_STRING_UTF8 u8"Is this a UTF8 string?"
#define CONST_STRING_16 u"What is this a UTF16 string?"
#define CONST_STRING_32 U"Hello using char32_t"
#define CONST_STRING_WIDE L"Hello with wchar_t"

#define CONST_INT_HEX 0xFF
#define CONST_INT_BIN 0b0101
#define CONST_INT_OCT 010
#define CONST_INT_ULL 232323ULL

#define CONST_INT_WITH_REF CONST_INT_OCT + CONST_INT_HEX

#define CONST_INT_CIRCULAR_2 CONST_INT_CIRCULAR_1 * 2
#define CONST_INT_CIRCULAR_1 CONST_INT_CIRCULAR_2 + 1

#define CONST_FLOAT 243.23e2f
#define CONST_DOUBLE 242.23e2

#if GEN_TEST_DEFINED
#define CONST_GLOBAL_DEF true
#else
#define CONST_GLOBAL_DEF false
#endif

#ifndef GEN_TEST_FORCEUNDEF
#define CONST_GLOBAL_UNDEF true
#else
#define CONST_GLOBAL_UNDEF false
#endif

#define STR(x, ...) #x
#define CONST_MACRO_STRINGIFY STR(""(123 + 123, +p),,,,,)

#define BF_ULL(x) x ## ULL
#define CONST_MACRO_EXPAND BF_ULL(55 + 55) 

typedef struct context {
	int handle;
	void* userdata;

	struct {
		int major, minor;
	} version;
	int i;
	struct {
		int x, y;
	} pos;
	struct {
		unsigned char r, g, b, a;
	} color;

} context;

typedef struct BitfieldsAreFun
{
	short a : 4;
	short b : 4;

	int x : 8;
	int y : 8;
	int z : 8;

	int w : 16;
	int v : 32;
} BitfieldsAreFun;


typedef enum qvtab {
	TAB_NONE,
	TAB_ONE,
	TAB_TWO,
	TAB_APPLE,
	TAB_TREE
} qvtab;

typedef struct qvalue qvalue;

struct module
{
	int (*xFindFunction)(qvtab *pVtab, int nArg, const char *zName,
		void (**pxFunc)(context*,int,qvalue**),
		void **ppArg);
};

__declspec(dllimport) int xFindFunction_Test(qvtab *pVtab, int nArg, const char *zName,
		void (**pxFunc)(context* ctx,int v,qvalue**),
		void **ppArg);

#endif // __TEST_H_