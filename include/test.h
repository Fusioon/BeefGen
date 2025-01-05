#ifndef __TEST_H__
#pragma once

#define CONST_CHAR8 '8'
#define CONST_CHAR8_HEX '\x72'
#define CONST_CHAR_UTF8 u8'\U0001f34c'
#define CONST_CHAR_UTF16 u'\U0001f34c'
#define CONST_CHAR_UTF32 U'\U0001f34c'
#define CONSTT_CHAR_WIDE L'č'

#define CONST_BOOL_FALSE false
#define CONST_BOOL_TRUE true

#define CONST_STRING8 "What is this"
#define CONST_STRING16 L"Hello with wchar_t"
#define CONST_STRING32 U"Hello using char32_t"

#define CONST_INT_HEX 0xFF
#define CONST_INT_ULL 232323ULL

#define CONST_FLOAT 243.23e2f
#define CONST_DOUBLE 242.23e2

#endif // __TEST_H_