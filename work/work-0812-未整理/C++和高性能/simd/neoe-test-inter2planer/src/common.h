#include <stdlib.h>
#include <stdio.h> // printf requires stdio.h, not stdlib.h


typedef unsigned short UINT16;
typedef short INT16;
typedef unsigned int UINT32;
typedef int INT32;
typedef unsigned char UINT8;
typedef char INT8;

#define DSP_ERROR (-1)
#define DSP_OK (0)

// Log level prefixes
#define DSP_LOG_ERROR(fmt, ...) printf("[ERROR] " fmt, ##__VA_ARGS__)  // ## removes the preceding comma when variadic args are empty (GCC extension)
#define DSP_LOG_WARN(fmt, ...)  printf("[WARN]  " fmt, ##__VA_ARGS__)
#define DSP_LOG_INFO(fmt, ...)  printf("[INFO]  " fmt, ##__VA_ARGS__)
#define HIK_IS_NULL(a) ((a)==NULL)




