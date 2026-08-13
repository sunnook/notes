
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <arm_neon.h>

#include "cycle_cnt.h"
#include "common.h"
#include "inter2planer.h"


INT32 priv_ao_copy_inter2plan0(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr)
{
     if(HIK_IS_NULL(pSrcAddr) || HIK_IS_NULL(pDstAddr))
    {
        DSP_LOG_ERROR("Addr is NULL src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }

    UINT32 uIdx = 0;
    UINT32 uASmpBytes = uBitWidth>>3;  // bytes per sample
    UINT32 uSmpNum = (uFrameLen/uASmpBytes);

    if(uFrameLen > uSmpNum*uASmpBytes)
    {
        DSP_LOG_WARN("Smaple Num not Good!!! uFrameLen:%d, uSmpNum:%d, uASmpBytes:%d!!!\n", uFrameLen, uSmpNum, uASmpBytes);
    }

    if(pSrcAddr == pDstAddr)
    {
        DSP_LOG_ERROR("Addr of src is same as dist, src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }
    else
    {
        for(uIdx=0; uIdx < uFrameLen; uIdx+=uASmpBytes)
        {
            memcpy(pDstAddr+uIdx, pSrcAddr+uIdx*2, uASmpBytes);
            memcpy(pDstAddr+uFrameLen+uIdx, pSrcAddr+uIdx*2+uASmpBytes, uASmpBytes);
        }
    }

    return DSP_OK;
}

INT32 priv_ao_copy_inter2plan1(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr)
{
    if(HIK_IS_NULL(pSrcAddr) || HIK_IS_NULL(pDstAddr))
    {
        DSP_LOG_ERROR("Addr is NULL src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }

    UINT32 uIdx = 0;
    UINT32 uASmpBytes = uBitWidth>>3;  // bytes per sample
    UINT32 uSmpNum = (uFrameLen/uASmpBytes);

    if(uFrameLen > uSmpNum*uASmpBytes)
    {
        DSP_LOG_WARN("Smaple Num not Good!!! uFrameLen:%d, uSmpNum:%d, uASmpBytes:%d!!!\n", uFrameLen, uSmpNum, uASmpBytes);
    }

    if(pSrcAddr == pDstAddr)
    {
        DSP_LOG_ERROR("Addr of src is same as dist, src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }
    else
    {
        {
            const INT16* pSrcAddr2 = (INT16*)pSrcAddr;
            INT16* pDstAddr2 = (INT16*)pDstAddr;
            for(uIdx=0; uIdx < uSmpNum; uIdx++)
            {
                pDstAddr2[uIdx] = pSrcAddr2[uIdx*2];
                pDstAddr2[uSmpNum+uIdx] = pSrcAddr2[uIdx*2+1];
            }
        }
    }

    return DSP_OK;
}


INT32 priv_ao_copy_inter2plan2(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr)
{
    if(HIK_IS_NULL(pSrcAddr) || HIK_IS_NULL(pDstAddr))
    {
        DSP_LOG_ERROR("Addr is NULL src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }

    if (uBitWidth != 16) // bit width check
    {
        DSP_LOG_ERROR("Only support 16bit in inter2plan2!!!\n");
        return DSP_ERROR;
    }

    UINT32 uASmpBytes = uBitWidth>>3;
    UINT32 uSmpNum = (uFrameLen/uASmpBytes);

    if(pSrcAddr == pDstAddr)
    {
        DSP_LOG_ERROR("Addr of src is same as dist, src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }
    else
    {
        const INT16* pSrc16 = (const INT16*)pSrcAddr;
        INT16* pDstL = (INT16*)pDstAddr;
        INT16* pDstR = (INT16*)(pDstAddr + uFrameLen); // right channel offset by uFrameLen bytes

        UINT32 uMainCnt = uSmpNum >> 2; 
        UINT32 uRemainCnt = uSmpNum & 3;

        // 4-way unrolled, interleave to planar
        while (uMainCnt--) 
        {
            *pDstL++ = *pSrc16++;  // L-1
            *pDstR++ = *pSrc16++;  // R-1
            *pDstL++ = *pSrc16++;  // L-2
            *pDstR++ = *pSrc16++;  // R-2
            *pDstL++ = *pSrc16++;  // L-3
            *pDstR++ = *pSrc16++;  // R-3
            *pDstL++ = *pSrc16++;  // L-4
            *pDstR++ = *pSrc16++;  // R-4
        }
        while (uRemainCnt--) 
        {
            *pDstL++ = *pSrc16++;
            *pDstR++ = *pSrc16++;
        }
    }

    return DSP_OK;
}


INT32 priv_ao_copy_inter2plan3(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr)
{
    if(HIK_IS_NULL(pSrcAddr) || HIK_IS_NULL(pDstAddr))
    {
        DSP_LOG_ERROR("Addr is NULL src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }

    if (uBitWidth != 16) // bit width check
    {
        DSP_LOG_ERROR("Only support 16bit in inter2plan3!!!\n");
        return DSP_ERROR;
    }

    UINT32 uASmpBytes = uBitWidth>>3;
    UINT32 uSmpNum = (uFrameLen/uASmpBytes);

    if(pSrcAddr == pDstAddr)
    {
        DSP_LOG_ERROR("Addr of src is same as dist, src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }
    else
    {
        const INT16* pSrc16 = (const INT16*)pSrcAddr;
        INT16* pDstL = (INT16*)pDstAddr;
        INT16* pDstR = (INT16*)(pDstAddr + uFrameLen);
        
        // uSmpNum is the number of samples per mono channel
        // Each vld2_s16 processes 4 samples (8 INT16 values)
        UINT32 uMainCnt = uSmpNum >> 2; 
        UINT32 uRemainCnt = uSmpNum & 3;

        while (uMainCnt--) 
        {
            // vld2_s16 loads interleaved data and deinterleaves automatically
            int16x4x2_t deinterleaved = vld2_s16(pSrc16);
            
            // store left and right channels separately
            vst1_s16(pDstL, deinterleaved.val[0]); 
            vst1_s16(pDstR, deinterleaved.val[1]); 
            
            pSrc16 += 8; // process 8 INT16 values per iteration
            pDstL += 4;
            pDstR += 4;
        }
        
        // handle remaining samples
        while (uRemainCnt--) 
        {
            *pDstL++ = *pSrc16++;
            *pDstR++ = *pSrc16++;
        }
    }

    return DSP_OK;
}


// INT32 priv_ao_copy_plan2inter3(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr)
// {
//   if(HIK_IS_NULL(pSrcAddr) || HIK_IS_NULL(pDstAddr))
//     {
//         DSP_LOG_ERROR("Addr is NULL src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
//         return DSP_ERROR;
//     }

//     UINT32 uIdx = 0;
//     // bytes per sample
//     UINT32 uSmpNum = (uFrameLen/uASmpBytes);

//     if(uFrameLen > uSmpNum*uASmpBytes)
//     {
//         DSP_LOG_WARN("Smaple Num not Good!!! uFrameLen:%d, uSmpNum:%d, uASmpBytes:%d!!!\n", uFrameLen, uSmpNum, uASmpBytes);
//     }

//     if(pSrcAddr == pDstAddr)
//     {
//         DSP_LOG_ERROR("Addr of src is same as dist, src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
//         return DSP_ERROR;
//     }
//     else
//     {
//         // if(16==uBitWidth)  // default bit width is 16bit
//         {
//             const UINT16* srcL = (const UINT16*)pSrcAddr;
//             const UINT16* srcR = (const UINT16*)(pSrcAddr + uFrameLen/2);
//             UINT16* dst = (UINT16*)pDstAddr;
            
//             // load interleaved data using vld2_s16
//             for (UINT32 i = 0; i < uSmpNum/4; i++) {
//                 int16x4x2_t interleaved;
//                 interleaved.val[0] = vld1_s16(srcL + i*4);   // load 4 left channel samples
//                 interleaved.val[1] = vld1_s16(srcR + i*4);   // load 4 right channel samples
//                 vst2_s16(dst + i*8, interleaved);    // store interleaved L R L R L R L R
//             }
            
//             // handle remaining samples
//             UINT32 remaining = uSmpNum % 4;
//             for (UINT32 i = uSmpNum - remaining; i < uSmpNum; i++) {
//                 dst[i*2] = srcL[i];
//                 dst[i*2+1] = srcR[i];
//             }
//         }
//     }

//     return DSP_OK;
// }


// INT32 ao_copy_inter2plan(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr)
// {
//     static UINT32 a = 0;
//     a++;
    
//     if(1==a)
//     {
//         priv_ao_copy_inter2plan0(pSrcAddr, uFrameLen, uBitWidth, pDstAddr);
//     }
//     else if(2==a)
//     {
//         priv_ao_copy_inter2plan1(pSrcAddr, uFrameLen, uBitWidth, pDstAddr);
//     }
//     else if(3==a)
//     {
//         priv_ao_copy_inter2plan2(pSrcAddr, uFrameLen, uBitWidth, pDstAddr);
//     }
//     else
//     {
//         priv_ao_copy_inter2plan3(pSrcAddr, uFrameLen, uBitWidth, pDstAddr);
//         a = 0;
//     }

//     return DSP_OK;
// }






   /*
   static INT32 priv_ao_copy_inter2plan1(const INT8* pSrcAddr, const UINT32 uFrameLen, const UINT32 uBitWidth, INT8* pDstAddr)
{
    if(HIK_IS_NULL(pSrcAddr) || HIK_IS_NULL(pDstAddr))
    {
        DSP_LOG_ERROR("Addr is NULL src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }

    UINT32 uIdx = 0;
    UINT32 uASmpBytes = uBitWidth>>3;  // bytes per sample
    UINT32 uSmpNum = (uFrameLen/uASmpBytes);

    if(uFrameLen > uSmpNum*uASmpBytes)
    {
        DSP_LOG_WARN("Smaple Num not Good!!! uFrameLen:%d, uSmpNum:%d, uASmpBytes:%d!!!\n", uFrameLen, uSmpNum, uASmpBytes);
    }

    if(pSrcAddr == pDstAddr)
    {
        DSP_LOG_ERROR("Addr of src is same as dist, src:0x%p dst:0x%p!!!\n", pSrcAddr, pDstAddr);
        return DSP_ERROR;
    }
    else
    {
        if((8==uBitWidth) || (16==uBitWidth) || (32==uBitWidth))
        {
            if(8==uBitWidth)
            {
                const INT8* pSrcAddr2 = pSrcAddr;
                INT8* pDstAddr2 = pDstAddr;
                for(uIdx=0; uIdx < uSmpNum; uIdx++)
                {
                    pDstAddr2[uIdx] = pSrcAddr2[uIdx*2];
                    pDstAddr2[uSmpNum+uIdx] = pSrcAddr2[uIdx*2+1];
                }
            }
            else if(16==uBitWidth)
            {
                const INT16* pSrcAddr2 = (INT16*)pSrcAddr;
                INT16* pDstAddr2 = (INT16*)pDstAddr;
                for(uIdx=0; uIdx < uSmpNum; uIdx++)
                {
                    pDstAddr2[uIdx] = pSrcAddr2[uIdx*2];
                    pDstAddr2[uSmpNum+uIdx] = pSrcAddr2[uIdx*2+1];
                }
            }
            else //if(32==uBitWidth)
            {
                const UINT32* pSrcAddr2 = (UINT32*)pSrcAddr;
                UINT32* pDstAddr2 = (UINT32*)pDstAddr;
                for(uIdx=0; uIdx < uSmpNum; uIdx++)
                {
                    pDstAddr2[uIdx] = pSrcAddr2[uIdx*2];
                    pDstAddr2[uSmpNum+uIdx] = pSrcAddr2[uIdx*2+1];
                }
            }
        }
        else
        {
            for(uIdx=0; uIdx < uFrameLen; uIdx+=uASmpBytes)
            {
                HIK_MEM_CPY(pDstAddr+uIdx, pSrcAddr+uIdx*2, uASmpBytes);
                HIK_MEM_CPY(pDstAddr+uFrameLen+uIdx, pSrcAddr+uIdx*2+uASmpBytes, uASmpBytes);
            }
        }
    }

    return DSP_OK;
}*/
