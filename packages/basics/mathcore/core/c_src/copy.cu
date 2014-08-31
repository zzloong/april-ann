/*
 * This file is part of the Neural Network modules of the APRIL toolkit (A
 * Pattern Recognizer In Lua).
 *
 * Copyright 2012, Salvador España-Boquera, Adrian Palacios Corella, Francisco
 * Zamora-Martinez
 *
 * The APRIL-MLP toolkit is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 */
#include "cblas_headers.h"
#include "cuda_utils.h"
#include "unused_variable.h"

namespace AprilMath {

#ifdef USE_CUDA
  /***************************************
   ************** CUDA SECTION ***********
   ***************************************/

  cublasStatus_t wrapperCublasCopy(cublasHandle_t &handle,
                                   int N,
                                   const float *x_mem,
                                   unsigned int x_inc,
                                   float *y_mem,
                                   unsigned int y_inc) {
    return cublasScopy(handle, N, x_mem, x_inc, y_mem, y_inc);
  }

  cublasStatus_t wrapperCublasCopy(cublasHandle_t &handle,
                                   int N,
                                   const ComplexF *x_mem,
                                   unsigned int x_inc,
                                   ComplexF *y_mem,
                                   unsigned int y_inc) {
    return cublasCcopy(handle, N, reinterpret_cast<const cuComplex*>(x_mem), x_inc,
                       reinterpret_cast<cuComplex*>(y_mem), y_inc);
  }

  template<typename T>
  __global__ void copyLoopKernel(unsigned int N,
                                 const T *x_mem,
                                 unsigned int x_inc,
                                 T *y_mem,
                                 unsigned int y_inc,
                                 unsigned int times,
                                 unsigned int y_ld) {
    unsigned int matrix_x_pos, matrix_y_pos;
    matrix_x_pos = blockIdx.x*blockDim.x + threadIdx.x;
    matrix_y_pos = blockIdx.y*blockDim.y + threadIdx.y;
    if (matrix_x_pos < times && matrix_y_pos < N) {
      unsigned int index_x = matrix_y_pos*x_inc;
      unsigned int index_y = matrix_x_pos*y_ld + matrix_y_pos*y_inc;
      y_mem[index_y] = x_mem[index_x];
    }
  }

#endif

  /***************************************
   ************* CBLAS SECTION ***********
   ***************************************/

  void wrapperCblasCopy(int N, const float *x_mem, unsigned int x_inc,
                        float *y_mem, unsigned int y_inc) {
    cblas_scopy(N, x_mem, x_inc, y_mem, y_inc);
  }

  void wrapperCblasCopy(int N, const ComplexF *x_mem, unsigned int x_inc,
                        ComplexF *y_mem, unsigned int y_inc) {
    cblas_ccopy(N, x_mem, x_inc, y_mem, y_inc);
  }

  /***************************************
   *********** TEMPLATE SECTION **********
   ***************************************/

  template<typename T>
  void doCopy(int N,
              const GPUMirroredMemoryBlock<T>* x,
              unsigned int x_inc,
              unsigned int x_shift,
              GPUMirroredMemoryBlock<T>* y,
              unsigned int y_inc,
              unsigned int y_shift,
              bool use_gpu)
  {
    const T *x_mem;
    T *y_mem;
#ifndef USE_CUDA
    UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
    if (use_gpu) {
      cublasStatus_t status;
      cublasHandle_t handle = GPUHelper::getHandler();
      //printf("Doing a scopy with comp=1 & cuda=1\n");
      x_mem = x->getGPUForRead() + x_shift;
      y_mem = y->getGPUForWrite() + y_shift;
    
      status = cublasSetStream(handle, GPUHelper::getCurrentStream());
      checkCublasError(status);
    
      status = wrapperCublasCopy(handle, N, x_mem, x_inc, y_mem, y_inc);
    
      checkCublasError(status);
    }
    else {
      //printf("Doing a scopy with comp=1 & cuda=0\n");
#endif
#ifndef USE_CUDA
      //printf("Doing a scopy with comp=0 & cuda=0\n");
#endif
      x_mem = x->getPPALForRead() + x_shift;
      y_mem = y->getPPALForWrite() + y_shift;

      wrapperCblasCopy(N, x_mem, x_inc, y_mem, y_inc);
#ifdef USE_CUDA
    }
#endif
  }

  template<typename T>
  void doCopyBroadcast(int N,
                       GPUMirroredMemoryBlock<T>* x,
                       unsigned int x_inc,
                       GPUMirroredMemoryBlock<T>* A,
                       unsigned int A_inc,
                       unsigned int times,
                       const unsigned int A_stride,
                       bool use_gpu)
  {
    const T *x_mem;
    T *A_mem;
#ifndef USE_CUDA
    UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
    if (use_gpu) {
      //printf("Doing a scopy with comp=1 & cuda=1\n");
      x_mem = x->getGPUForRead();
      A_mem = A->getGPUForWrite();

      const unsigned int MAX_THREADS = GPUHelper::getMaxThreadsPerBlock();
      dim3 block, grid;
      // Number of threads on each block dimension
      block.x = min(MAX_THREADS, times);
      block.A = min(MAX_THREADS/block.x, N);
      block.z = 1;

      grid.x = (times/block.x +
                (times % block.x ? 1 : 0));
      grid.A = (N/block.A + (N % block.A ? 1 : 0));
      grid.z = 1;

      copyLoopKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
        (N, x_mem, x_inc, A_mem, A_inc, times, stride);
    }
    else {
      //printf("Doing a scopy with comp=1 & cuda=0\n");
#endif
#ifndef USE_CUDA
      //printf("Doing a scopy with comp=0 & cuda=0\n");
#endif
      x_mem = x->getPPALForRead();
      A_mem = A->getPPALForWrite();

      for (unsigned int i = 0; i < times; i++)
        wrapperCblasCopy(N, 
                         x_mem, x_inc,
                         A_mem + i * A_stride , A_inc);
#ifdef USE_CUDA
    }
#endif
  }

  template void doCopy<float>(int, const GPUMirroredMemoryBlock<float>*,
                              unsigned int,
                              unsigned int,
                              GPUMirroredMemoryBlock<float>*,
                              unsigned int,
                              unsigned int,
                              bool);
  template void doCopy<ComplexF>(int, const GPUMirroredMemoryBlock<ComplexF>*,
                                 unsigned int,
                                 unsigned int,
                                 GPUMirroredMemoryBlock<ComplexF>*,
                                 unsigned int,
                                 unsigned int,
                                 bool);

  template void doCopyBroadcast<float>(int,
                                       GPUMirroredMemoryBlock<float>*,
                                       unsigned int,
                                       GPUMirroredMemoryBlock<float>*,
                                       unsigned int,
                                       unsigned int,
                                       const unsigned int,
                                       bool);
  template void doCopyBroadcast<ComplexF>(int,
                                          GPUMirroredMemoryBlock<ComplexF>*,
                                          unsigned int,
                                          GPUMirroredMemoryBlock<ComplexF>*,
                                          unsigned int,
                                          unsigned int,
                                          const unsigned int,
                                          bool);

} // namespace AprilMath
