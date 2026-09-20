#ifndef __khrplatform_h_
#define __khrplatform_h_

#include <stdint.h>
#include <stddef.h>

typedef int32_t                 khronos_int32_t;
typedef uint32_t                khronos_uint32_t;
typedef int64_t                 khronos_int64_t;
typedef uint64_t                khronos_uint64_t;
typedef signed   char           khronos_int8_t;
typedef unsigned char           khronos_uint8_t;
typedef signed   short int      khronos_int16_t;
typedef unsigned short int      khronos_uint16_t;
typedef float                   khronos_float_t;
typedef signed   long  int      khronos_intptr_t;
typedef unsigned long  int      khronos_uintptr_t;
typedef signed   long  int      khronos_ssize_t;
typedef unsigned long  int      khronos_usize_t;

#define KHRONOS_APICALL
#define KHRONOS_APIENTRY

#endif
