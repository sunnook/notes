#include <stdlib.h>

#include "common.h"

/* Interleave to planar format conversion functions.
 * These functions convert interleaved stereo audio data (LRLRLR...)
 * to planar format (all left samples followed by all right samples). */
INT32 priv_ao_copy_inter2plan0(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr);


INT32 priv_ao_copy_inter2plan1(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr);

INT32 priv_ao_copy_inter2plan2(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr);

INT32 priv_ao_copy_inter2plan3(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr);
